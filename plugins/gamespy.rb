mobius_plugin(name: "GameSpy", version: "0.0.1") do
  MasterServer = Struct.new(:socket)

  on(:start) do
    @query_id = 10
    @flood = {}
    @bans = {}

    @master_servers = []
    @query_socket = UDPSocket.new
    @query_port = Config.gamespy[:query_port]

    failure = false

    after(5) do
      log "Started Announcer"

      begin
        @query_socket.bind("0.0.0.0", @query_port)
      rescue Errno::EADDRINUSE
        failure = true
        log "Failed to start query server, address already in use!"
      end

      unless failure
        Config.gamespy[:master_servers].each do |address|
          host, port = address.split(":")
          socket = UDPSocket.new

          socket.connect(host, port)

          @master_servers << socket

          send_heartbeat_to_master(socket)
        end
      end

      unless failure
        every(1) do
          handle_sockets
        end

        every(300) do
          log "Sending heartbeat..."
          @master_servers.each do |ms|
            send_heartbeat_to_master(ms)
          end
        end
      end
    end
  end

  on(:shutdown) do
    log "SHUTTING DOWN MASTER SERVERS..."

    @query_socket&.close

    @master_servers.each do |s|
      send_heartbeat_stop_to_master(s)
      s&.close
    end
  end

  def bool_to_int(bool)
    bool ? "1" : "0"
  end

  def handle_sockets
    begin
      loop do
        message, addrinfo = @query_socket.recvfrom_nonblock(2048)

        query_server_receive(message, addrinfo)
      end
    rescue IO::WaitReadable
      # Nothing available to read
    end

    @master_servers.each do |socket|
      begin
        loop do
          message, addrinfo = socket.recvfrom_nonblock(2048)

          #query_server_receive(message, addrinfo)
        end
      rescue IO::WaitReadable
        # Nothing available to read
      end
    end
  end

  def send_heartbeat_to_master(socket)
    socket.send("\\heartbeat\\#{@query_port}\\gamename\\cncrenegade", 0)
  end

  def send_heartbeat_stop_to_master(socket)
    socket.send("\\heartbeat\\#{@query_port}\\gamename\\cncrenegade\\statechanged\\2", 0)
  end

  def query_server_receive(message, addrinfo)
    # TODO: handle ban checking

    reply = case message
            when "\\basic\\"
              generate_basic
            when "\\info\\"
              generate_info
            when "\\rules\\"
              generate_rules
            end

    if message.start_with?("\\echo\\")
      # _, echo = message.split("\\echo\\")

      log "ECHO: #{message}"

      reply = message
    end

    if reply
      @query_id += 1

      @query_socket.send("#{reply}\\final\\queryid\\#{@query_id}.1", 0, addrinfo[2], addrinfo[1])
    end

    if message.start_with?("\\players\\") || message.start_with?("\\status\\")
      @query_id += 1
      index = 1

      if message.start_with?("\\status\\")
        reply = "#{generate_basic}#{generate_info}#{generate_rules}\\queryid\\#{@query_id}.#{index}"
        @query_socket.send(reply, 0, addrinfo[2], addrinfo[1])

        index += 1
      end

      player_fragments, team_fragment = generate_players

      player_fragments.each do |fragment|
        @query_socket.send("#{fragment}\\queryid\\#{@query_id}.#{index}", 0, addrinfo[2], addrinfo[1])
        index += 1
      end

      @query_socket.send("#{team_fragment}\\final\\queryid\\#{@query_id}.#{index}", 0, addrinfo[2], addrinfo[1])
    end
  end

  def generate_basic
    "\\gamename\\ccrenegade\\gamever\\838"
  end

  def generate_info
    "\\hostname\\#{ServerConfig.server_name}" \
    "\\hostport\\#{ServerConfig.server_port}" \
    "\\mapname\\#{ServerStatus.get(:current_map)}" \
    "\\gametype\\#{Config.gamespy[:game_type]}" \
    "\\numplayers\\#{ServerStatus.total_players}" \
    "\\maxplayers\\#{ServerStatus.get(:max_players)}"
  end

  def generate_rules
    string = "\\CSVR\\1" \
             "\\DED\\1" \
             "\\password\\#{ServerStatus.get(:has_password)}" \
             "\\DG\\#{bool_to_int(ServerConfig.driver_gunner)}" \
             "\\TC\\#{bool_to_int(ServerConfig.team_changing)}" \
             "\\FF\\#{bool_to_int(ServerConfig.friendly_fire)}" \
             "\\SC\\#{ServerConfig.starting_credits}" \
             "\\SSC\\Mobius v#{Mobius::VERSION}" \
             "\\timeleft\\#{ServerStatus.get(:time_remaining)}"

    Config.gamespy[:custom_info].each do |key, value|
      string += "\\#{key}\\#{value}"
    end

    string
  end

  def generate_players
    fragments = []

    PlayerData.player_list.each_slice(15) do |slice|
      slice.each_with_index do |player, i|
        string = ""
        string += "\\player_#{i}\\#{player.name}"
        string += "\\score_#{i}\\#{player.score}"
        string += "\\ping_#{i}\\#{player.ping}"
        string += "\\team_#{i}\\#{player.team}"
        string += "\\kills_#{i}\\#{player.kills}"
        string += "\\deaths_#{i}\\#{player.deaths}"

        fragments << string
      end
    end

    team0_score = ServerStatus.get(:team_0_points)
    team1_score = ServerStatus.get(:team_1_points)

    [fragments, "\\team_t0\\#{Teams.name(0)}\\score_t0\\#{team0_score}\\team_t1\\#{Teams.name(1)}\\score_t1\\#{team1_score}"]
  end
end
