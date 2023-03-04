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

  def connect_to_bridge
    this = self
    @connection_error = false

    log "WEBSOCKET ALREADY EXISTS: #{@ws}" if @ws

    Thread.new do
      begin
        WebSocket::Client::Simple.connect("ws://localhost:3000/api/v1/websocket") do |ws|
          this.websocket = ws

          ws.on(:open) do
            this.log "connected!"
          end

          ws.on(:message) do |msg|
            this.log msg.data
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

  def websocket=(ws)
    @ws = ws
  end

  def deliver(payload)
    payload[:uuid] = @uuid

    if @ws.nil? || @ws&.closed?
      log "---- Connection Error? #{@connection_error}"
    else
      log payload
      @ws.send(payload.to_json)
    end
  end

  on(:start) do
    unless Config.discord_bridge && !Config.discord_bridge[:url].to_s.empty?
      log "Missing configuration data or invalid url"
      PluginManager.disable_plugin(self)

      next
    end

    @uuid = Config.discord_bridge[:uuid]
    @send_status = true

    connect_to_bridge

    every(5) do
      connect_to_bridge if @connection_error || @ws.nil?
      @connection_error = false

      if @send_status
        deliver(full_payload)
        @send_status = false
        @status_last_sent = monotonic_time
      end
    end

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

  on(:player_left) do
    # Event is fired BEFORE player data is removed
    after(3) do
      @send_status = true
    end
  end

  on(:shutdown) do
    connection_error! if @ws
  end
end
