mobius_plugin(name: "DiscordBridgeAgent", database_name: "discord_bridge_agent", version: "0.0.1") do
  def full_payload
    teams = Teams.list.each.map do |team|
      {
        name: team[:name],
        team_players: PlayerData.players_by_team(team[:id]).count,
        score: team[:id] <= 1 ? ServerStatus.get(:"team_#{team[:id]}_points") : PlayerData.players_by_team(2).map(&:score).sum
      }
    end

    players = PlayerData.player_list.select(&:ingame?).map do |player|
      h = {
        name: player.name,
        score: player.score,
        team: player.team
      }

      h[:spy] = true if @known_spies[player.name]

      h
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

  def message_discord_id(discord_id, message, type = nil)
    {
      type: :message,
      data: {
        discord_id: discord_id,
        message: message,
        type: type
      }
    }
  end

  def verify_staff(discord_id, player)
    ip_trustable = true

    Config.staff.each do |level, list|
      found = false

      list.each do |hash|
        next unless hash[:name].downcase == player.name.downcase

        ip_trustable = hash[:ip_trustable] == nil ? true : hash[:ip_trustable]
        found = true

        break
      end

      break if found
    end

    {
      type: :verify_staff,
      data: {
        discord_id: discord_id,
        nickname: player.name,
        ip_address: player.address.split(";").first,
        ip_trustable: ip_trustable,
        server_name: ServerConfig.server_name
      }
    }
  end

  def manage_voice_channels(issuer_nickname:, lobby: false, teamed: false, move: false, discord_name: "", voice_channel: nil)
    hash = {
      type: :manage_voice_channels,
      data: {
        issuer_nickname: issuer_nickname
      }
    }

    hash[:data][:lobby] = true if lobby
    hash[:data][:teamed] = true if teamed

    if move
      hash[:data][:move] = true
      hash[:data][:discord_name] = discord_name
      hash[:data][:voice_channel] = voice_channel
    end

    hash
  end

  def fetch_staff(auth_channel)
    {
      type: :fetch_staff,
      data: {
        auth_channel: auth_channel
      }
    }
  end

  def waiting_for_reply?(discord_id)
    @staff_pending_verification[discord_id]
  end

  def verify_timeout(discord_id)
    pending_staff = @staff_pending_verification[discord_id]

    return 0 unless pending_staff

    (@verification_timeout - (monotonic_time - pending_staff[:time])).round
  end

  def check_pending_staff_verifications!
    @staff_pending_verification.each do |discord_id, hash|
      if (monotonic_time - hash[:time]) >= @verification_timeout
        kick_player!(hash[:player], "Protected username: You failed to verify in time!")

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
        deliver(message_discord_id(discord_id, "**OKAY**: Communication with FDS restored!", :admin))
      else
        deliver(message_discord_id(discord_id, "**ERROR**: Unable to communicate with FDS!", :admin))
      end
    end
  end

  def connect_to_bridge
    this = self
    @connection_error = false
    @last_connection_attempt = monotonic_time

    log "Connecting..."
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
            # this.log msg.data
            this.handle_message(msg.data)
          end

          ws.on(:close) do |error|
            this.log error

            this.connection_error!
          end

          ws.on(:error) do |error|
            this.log error

            this.connection_error!
          end
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => error
        this.log error

        this.connection_error!
      end
    end
  end

  def connection_error!
    @connection_error = true
    @ws&.close
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
    payload[:_queued_time] = monotonic_time

    @send_queue << payload unless @ws.nil? || @ws&.closed?
  end

  def handle_message(msg)
    hash = JSON.parse(msg, symbolize_names: true)

    # pp hash

    case hash[:type].to_s.downcase.to_sym
    when :verify_staff
      discord_id = hash[:data][:discord_id]

      if (pending_staff = @staff_pending_verification[discord_id])
        verified = hash[:data][:verified]

        if verified
          PluginManager.publish_event(:_discord_bot_verified_staff, pending_staff[:player], discord_id)
          page_player(pending_staff[:player], "Welcome back, Commander!")
          deliver(message_discord_id(discord_id, "Welcome back, Commander!"))
          @staff_pending_verification.delete(discord_id)
        else
          # Kick imposter
          kick_player!(pending_staff[:player], "Protected username: You are an imposter!")
          deliver(message_discord_id(discord_id, "Roger, imposter has been kicked."))
          @staff_pending_verification.delete(discord_id)
        end
      end

    when :message
      player = PlayerData.player(PlayerData.name_to_id(hash[:data][:nickname]))

      page_player(player, "[DiscordBridgeAgent] #{hash[:data][:message]}") if player

    when :voice_channel_changed
      @voice_channel_data = hash
      @voice_channel_data_updated = true

    when :fetch_staff
      handle_fetch_staff(hash[:data])
    end
  end

  def handle_voice_channel_data(hash)
    joined_voice = []
    left_voice   = []

    # Detect joins and sync active channel
    [:lobby, :team_0, :team_1].each do |list|
      hash[:data][:players][list].each do |username|
        player = PlayerData.player(PlayerData.name_to_id(username))

        next unless player

        channel = case list
                  when :lobby
                    "Lobby"
                  when :team_0
                    Teams.name(0)
                  when :team_1
                    Teams.name(1)
                  end

        # Player cannot join the same channel repeatedly
        next if player.value(:discord_voice_channel) == channel

        player.set_value(:discord_voice_channel, channel)

        joined_voice << [player, channel]
      end
    end

    # Detect leaves
    in_voice_channels = hash[:data][:players].values.flatten.uniq.map(&:downcase)
    PlayerData.player_list.each do |player|
      in_voice_channel = in_voice_channels.include?(player.name.downcase)

      # Player is in a voice channel, as such they haven't left
      next if in_voice_channel

      channel = player.value(:discord_voice_channel)

      # Player can only leave if they've been in a voice channel
      next unless channel

      player.delete_value(:discord_voice_channel)

      left_voice << [player, channel]
    end

    @voice_channel_data_updated = false

    return unless @announce_voice_channel_changes

    counters = [
      PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == Teams.name(0).downcase }.size,
      PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == Teams.name(1).downcase }.size,
      PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == "lobby" }.size
    ]

    if @suppress_voice_channel_changes
      broadcast_voice_channel_info

      return
    end

    joined_voice.each do |player, channel|
      count_string = channel.to_s.downcase == "lobby" ? "(#{counters[2]}/#{PlayerData.player_list.size})" : "(#{counters[player.team] || 0}/#{PlayerData.players_by_team(player.team).size})"
      broadcast_message("[DiscordBridgeAgent] #{player.name} joined the #{channel} voice channel #{count_string}", red: 255, green: 127, blue: 0)
    end

    left_voice.each do |player, channel|
      count_string = channel.to_s.downcase == "lobby" ? "(#{counters[2]}/#{PlayerData.player_list.size})" : "(#{counters[player.team] || 0}/#{PlayerData.players_by_team(player.team).size})"
      broadcast_message("[DiscordBridgeAgent] #{player.name} left the #{channel} voice channel (#{count_string})", red: 255, green: 127, blue: 0)
    end
  end

  def broadcast_voice_channel_info
    counter = {
      lobby:  PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == "lobby" }.size,
      team_0: PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == Teams.name(0).downcase }.size,
      team_1: PlayerData.player_list.select { |ply| ply.value(:discord_voice_channel).to_s.downcase == Teams.name(1).downcase }.size
    }

    team_0_str = "#{Teams.name(0)}: #{counter[:team_0]}/#{PlayerData.players_by_team(0).size}"
    team_1_str = "#{Teams.name(1)}: #{counter[:team_1]}/#{PlayerData.players_by_team(1).size}"
    string = "Lobby: #{counter[:lobby]}, #{team_0_str}, #{team_1_str}"

    broadcast_message("[MOBIUS] Players in voice channels: #{string}", red: 255, green: 127, blue: 0)
  end

  def handle_fetch_staff(hash)
    if hash[:okay]
      Config.staff[:admin] = hash[:hash][:admin] || []
      Config.staff[:mod] = hash[:hash][:mod] || []
      Config.staff[:director] = hash[:hash][:director] || []

      log "Updated staff from bridge. (#{hash[:auth_channel]})"
    else
      log "Failed to retreive staff from bridge. (#{hash[:auth_channel]})"
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
    @announce_voice_channel_changes = Config.discord_bridge[:announce_voice_channel_changes]
    @suppress_voice_channel_changes = false
    @voice_channel_data = nil
    @voice_channel_data_updated = false
    @send_status = true
    @auth_channel = Config.discord_bridge[:auth_channel]

    @fds_responding = database_get("fds_responding") == "true"
    @staff_pending_verification = {}
    @verification_timeout = 65 # seconds

    @last_connection_attempt = 0.0
    @status_last_sent = 0

    @known_spies = {}

    connect_to_bridge

    after(5) do
      deliver(fetch_staff(@auth_channel)) if @auth_channel
    end

    every(15) do
      @send_status = true if monotonic_time - @status_last_sent >= 15.0
    end
  end

  on(:player_joined) do
    @send_status = true
  end

  on(:map_loaded) do
    deliver(fetch_staff(@auth_channel)) if @auth_channel

    @send_status = true
    @known_spies = {}

    @suppress_voice_channel_changes = true

    after(15) do
      @suppress_voice_channel_changes = false
    end
  end

  on(:config_reloaded) do
    deliver(fetch_staff(@auth_channel)) if @auth_channel
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
    # Reconnect to bridge if there is a connection error
    connect_to_bridge if @connection_error && monotonic_time - @last_connection_attempt >= 7.0

    # Manage staff verifications
    check_pending_staff_verifications!

    # Send fds status to server owner(s)
    if ServerStatus.get(:fds_responding) != @fds_responding
      @send_status = true
      @fds_responding = ServerStatus.get(:fds_responding)
      database_set("fds_responding", @fds_responding)

      page_server_administrators!
    else
      # Queue full payload / status if @send_status is true
      if @send_status && @fds_responding
        deliver(full_payload)

        @send_status = false
        @status_last_sent = monotonic_time
      end
    end

    # Don't send and drop old messages
    @send_queue.each do |message|
      next unless monotonic_time - message[:_queued_time] >= 60.0

      @send_queue.delete(message)
    end

    # Send queued messages
    if @ws && !@ws.closed? && @ws.open?
      while (message = @send_queue.shift)
        @ws.send(message.to_json)
      end
    end

    # Sync voice channel data and send channel announcements
    handle_voice_channel_data(@voice_channel_data) if @voice_channel_data_updated
  end

  on(:created) do |hash|
    player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

    next unless player

    team_in_flux = false

    case hash[:type].downcase
    when "soldier"
      if hash[:preset].downcase.include?("_spy_")
        @known_spies[player.name] = true
        team_in_flux = true
      elsif @known_spies.delete(player.name)
        team_in_flux = true
      end
    end

    # Prevent/mitigate voice channel change spam due to player team not in sync
    if team_in_flux
      RenRem.cmd("pinfo")

      after(1) do
        @send_status = true
      end
    end
  end

  on(:_discord_bot_verify_staff) do |player, discord_id|
    next if waiting_for_reply?(discord_id)

    after(5) do # 60 seconds left
      if @staff_pending_verification[discord_id]
        page_player(player, "[MOBIUS] Protected nickname, please authenticate via DISCORD")

        after(10) do # 50 seconds left
          if @staff_pending_verification[discord_id]
            page_player(player, "[MOBIUS] Protected nickname, please authenticate via DISCORD within the next #{verify_timeout(discord_id)} seconds or you will be kicked.")

            after(20) do # 30 seconds left
              if @staff_pending_verification[discord_id]
                page_player(player, "[MOBIUS] Protected nickname, please authenticate via DISCORD within the next #{verify_timeout(discord_id)} seconds or you will be kicked.")

                after(20) do # 10 seconds left
                  if @staff_pending_verification[discord_id]
                    page_player(player, "[MOBIUS] Protected nickname, please authenticate via DISCORD within the next #{verify_timeout(discord_id)} seconds or you will be kicked.")
                  end
                end
              end
            end
          end
        end
      end
    end

    @staff_pending_verification[discord_id] = { player: player, time: monotonic_time }

    deliver(verify_staff(discord_id, player))
  end

  on(:_authenticated) do |player, hash|
    if (discord_id = hash[:discord_id])
      # FIXME: Tell Bridge to update or delete confirmation prompt
      log "#{player.name} externally authenticated." if @staff_pending_verification.delete(discord_id)
    end
  end

  on(:shutdown) do
    connection_error! if @ws
  end

  command(:vc_info, aliases: [:vci], arguments: 0, help: "!vc_info - List players in voice channels") do |command|
    broadcast_voice_channel_info
  end

  command(:vc_lobby, aliases: [:vcl], arguments: 0, help: "!vc_lobby - Moves everyone in teamed voice channels into lobby channel", groups: [:admin, :mod]) do |command|
    deliver(manage_voice_channels(lobby: true, issuer_nickname: command.issuer.name))
    page_player(command.issuer, "[DiscordBridgeAgent] Requesting to move all users in teamed voice channels to lobby channel, one moment...")
  end

  command(:vc_teamed, aliases: [:vct], arguments: 0, help: "!vc_teamed - Moves known players from lobby channel into teamed voice channels", groups: [:admin, :mod]) do |command|
    deliver(manage_voice_channels(teamed: true, issuer_nickname: command.issuer.name))
    page_player(command.issuer, "[DiscordBridgeAgent] Requesting to move known players from lobby voice channel to teamed channels, one moment...")
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
    page_player(command.issuer, "[DiscordBridgeAgent] Requesting to move #{discord_name} to #{channel.is_a?(Integer) ? Teams.name(channel) : channel.capitalize} voice channel, one moment...")
  end
end
