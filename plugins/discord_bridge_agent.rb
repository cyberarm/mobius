mobius_plugin(name: "DiscordBridgeAgent", version: "0.0.1") do
  def full_payload
    teams = Teams.list.select { |t| t[:id] <= 1 }.map do |team|
      {
        name: team[:name],
        team_players: PlayerData.players_by_team(team[:id]).count,
        score: ServerStatus.get(:"team_#{team[:id]}_points") || 0
      }
    end

    players = PlayerData.player_list.select(&:ingame?).map do |player|
      {
        name: player.name,
        score: player.score,
        team: player.team
      }
    end

    coop = {
      team_0_bot_count: PluginManager.blackboard(:team_0_bot_count).to_i,
      team_1_bot_count: PluginManager.blackboard(:team_1_bot_count).to_i
    }

    server_color = Config.discord_bridge[:server_color]
    server_color = server_color.to_i(16) if server_color

    status = {
      type: :status,
      data: {
        server_name: ServerConfig.server_name,
        server_color: server_color,
        battleview_url: Config.discord_bridge[:battleview_url],
        map_name: ServerStatus.get(:current_map),
        time_left: ServerStatus.get(:time_remaining),
        player_count: PlayerData.player_list.count,
        max_players: ServerStatus.get(:max_players),
        teams: teams,
        players: players,
        coop: coop
      }
    }

    status[:data].delete(:coop) if coop.values.map(&:to_i).sum.zero?

    status
  end

  def message_discord_id(discord_id, message)
    {
      type: :message,
      data: {
        discord_id: discord_id,
        message: message
      }
    }
  end

  def verify_staff(discord_id, nickname)
    {
      type: :verify_staff,
      data: {
        discord_id: discord_id,
        nickname: nickname,
        server_name: ServerConfig.server_name
      }
    }
  end

  def manage_voice_channels(issuer_nickname:, lobby: false, competitive: false, move: false, discord_name: "", voice_channel: nil)
    hash = {
      type: :manage_voice_channels,
      data: {
        issuer_nickname: issuer_nickname
      }
    }

    hash[:data][:lobby] = true if lobby
    hash[:data][:competitive] = true if competitive

    if move
      hash[:data][:move] = true
      hash[:data][:discord_name] = discord_name
      hash[:data][:voice_channel] = voice_channel
    end

    hash
  end

  def waiting_for_reply?(discord_id)
    @staff_pending_verification[discord_id]
  end

  def check_pending_staff_verifications!
    @staff_pending_verification.each do |discord_id, hash|
      if (monotonic_time - hash[:time]) >= @verification_timeout
        kick_player!(hash[:player].name, "Protected username: You failed to verify in time!")

        @staff_pending_verification.delete(discord_id)
      end
    end
  end

  def page_server_administrators!
    Config.staff[:admin].each do |hash|
      next unless (discord_id = hash[:discord_id])
      next unless hash[:server_owner]

      server_name = ServerConfig.server_name || Config.discord_bridge[:server_short_name].upcase

      if @fds_responding
        deliver(message_discord_id(discord_id, "**OKAY** `#{server_name}`: Communication with FDS restored!"))
      else
        deliver(message_discord_id(discord_id, "**ERROR** `#{server_name}`: Unable to communicate with FDS!"))
      end
    end
  end

  def connect_to_bridge
    this = self
    @connection_error = false

    log "WEBSOCKET ALREADY EXISTS: #{@ws}" if @ws

    Thread.new do
      begin
        WebSocket::Client::Simple.connect("#{Config.discord_bridge[:url]}/api/v1/websocket") do |ws|
          this.websocket = ws

          ws.on(:open) do
            this.log "connected!"
            this.schedule_status_update!
          end

          ws.on(:message) do |msg|
            this.log msg.data
            this.handle_message(msg.data)
          end

          ws.on(:error) do |error|
            this.log error

            this.connection_error!
          end
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        connection_error!
      end
    end
  end

  def connection_error!
    @connection_error = true
    @ws.close
    self.websocket = nil
  end

  def schedule_status_update!
    @send_status = true
  end

  def websocket=(ws)
    @ws = ws
  end

  def deliver(payload)
    payload[:uuid] = @uuid

    if @ws.nil? || @ws&.closed?
      log "---- Connection Error? #{@connection_error}"
    else
      # log payload
      @send_queue << payload.to_json
    end
  end

  def handle_message(msg)
    hash = JSON.parse(msg, symbolize_names: true)

    pp hash

    case hash[:type].to_s.downcase.to_sym
    when :verify_staff
      discord_id = hash[:data][:discord_id]

      if (pending_staff = @staff_pending_verification[discord_id])
        verified = hash[:data][:verified]

        if verified
          PluginManager.publish_event(:_discord_bot_verified_staff, pending_staff[:player], discord_id)
          page_player(pending_staff[:player].name, "Welcome back, Commander!")
          deliver(message_discord_id(discord_id, "Welcome back, Commander!"))
          @staff_pending_verification.delete(discord_id)
        else
          # Kick imposter
          kick_player!(pending_staff[:player].name, "Protected username: You are an imposter!")
          deliver(message_discord_id(discord_id, "Roger, imposter has been kicked."))
          @staff_pending_verification.delete(discord_id)
        end
      end

    when :message
      player = PlayerData.player(PlayerData.name_to_id(hash[:data][:nickname]))

      page_player(player.name, "[DiscordBridgeAgent] #{hash[:data][:message]}") if player
    end
  end

  on(:start) do
    unless Config.discord_bridge && !Config.discord_bridge[:url].to_s.empty?
      log "Missing configuration data or invalid url"
      PluginManager.disable_plugin(self)

      next
    end

    @send_queue = []

    @uuid = Config.discord_bridge[:uuid]
    @send_status = true

    @fds_responding = true
    @staff_pending_verification = {}
    @verification_timeout = 65 # seconds

    connect_to_bridge

    every(15) do
      @send_status = true if monotonic_time - @status_last_sent >= 15.0
    end
  end

  on(:player_joined) do
    @send_status = true
  end

  on(:map_loaded) do
    @send_status = true
  end

  on(:team_changed) do
    @send_status = true
  end

  on(:player_left) do |player|
    @staff_pending_verification.each do |key, hash|
      next unless hash[:player].name == player.name

      log "Removing pending verification for #{player.name}"
      @staff_pending_verification.delete(key)
    end

    # Event is fired BEFORE player data is removed
    after(3) do
      @send_status = true
    end
  end

  on(:tick) do
    # Reconnect to bridge of there is a connection error
    connect_to_bridge if @connection_error || @ws.nil?

    # Manage staff verifications
    check_pending_staff_verifications!

    # Send fds status to server owner(s)
    if ServerStatus.get(:fds_responding) != @fds_responding
      @send_status = true
      @fds_responding = ServerStatus.get(:fds_responding)

      page_server_administrators!
    end

    # Queue full payload / status if @send_status is true
    if @send_status
      deliver(full_payload)

      @send_status = false
      @status_last_sent = monotonic_time
    end

    # Send queued messages
    if @ws && !@ws.closed? && @ws.open?
      while (message = @send_queue.shift)
        @ws.send(message)
      end
    end
  end

  on(:_discord_bot_verify_staff) do |player, discord_id|
    next if waiting_for_reply?(discord_id)

    after(5) do
      if @staff_pending_verification[discord_id]
        page_player(player.name, "Protected nickname, please authenticate via Discord within the next #{@verification_timeout - 5} seconds or you will be kicked.")
      end
    end

    @staff_pending_verification[discord_id] = { player: player, time: monotonic_time }

    deliver(verify_staff(discord_id, player.name))
  end

  on(:shutdown) do
    connection_error! if @ws
  end

  command(:vc_lobby, aliases: [:vcl], arguments: 0, help: "!vc_lobby - Moves everyone in teamed voice channels into lobby channel", groups: [:admin, :mod]) do |command|
    deliver(manage_voice_channels(lobby: true, issuer_nickname: command.issuer.name))
    page_player(command.issuer.name, "[DiscordBridgeAgent] Requesting to move all users in teamed voice channels to lobby channel, one moment...")
  end

  command(:vc_competitive, aliases: [:vcc], arguments: 0, help: "!vc_competitive - Moves known players from lobby channel into teamed voice channels", groups: [:admin, :mod]) do |command|
    deliver(manage_voice_channels(competitive: true, issuer_nickname: command.issuer.name))
    page_player(command.issuer.name, "[DiscordBridgeAgent] Requesting to move known players from lobby voice channel to teamed channels, one moment...")
  end

  command(:vc_move, aliases: [:vcm], arguments: 2, help: "!vc_move <discord name> <team or lobby> - Moves Discord user from lobby or teamed channel in to lobby or teamed channel (Moving player between teamed channels may not work if their nickname matches their Discord name and the teamed channel isn't the team they're on)", groups: [:admin, :mod]) do |command|
    discord_name = command.arguments.first
    channel = command.arguments.last

    begin
      channel = Integer(channel)
    rescue ArgumentError
      channel = Teams.id_from_name(channel)&.dig(:id) || "lobby"
    end

    deliver(manage_voice_channels(move: true, discord_name: discord_name, voice_channel: channel, issuer_nickname: command.issuer.name))
    page_player(command.issuer.name, "[DiscordBridgeAgent] Requesting to move #{discord_name} to #{channel.is_a?(Integer) ? Teams.name(channel) : channel.capitalize} voice channel, one moment...")
  end
end
