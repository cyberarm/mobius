mobius_plugin(name: "GameSpy", version: "0.0.1") do
  MasterServer = Struct.new(:socket)

  on(:start) do
    @query_id = 1
    @fragment_id = 1
    @query_address = nil
    @flood = {}
    @bans = {}

    @buffer = StringIO.new

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

    @buffer.string = ""
    @query_address = addrinfo
    @fragment_id = 1

    case message
    when "\\basic\\"
      generate_basic
    when "\\info\\"
      generate_info
    when "\\rules\\"
      generate_rules
    when "\\status\\"
      "#{generate_basic}#{generate_info}#{generate_rules}#{generate_players}"
    when "\\echo\\"
      append_fragment("\\echo\\#{message[6..message.length - 1]}") # echo back received message less \echo\
    end

    @query_socket.send("#{@buffer.string}\\final\\queryid\\#{@query_id}.#{@fragment_id}", 0, @query_address[2], @query_address[1])

    @buffer.string = ""
    @query_address = nil
    @fragment_id = 1
  end

  def append_fragment(string)
    @buffer.write(string)

    return unless @buffer.size > 400

    @query_socket.send("#{@buffer.string}\\queryid\\#{@query_id}.#{@fragment_id}", 0, @query_address[2], @query_address[1])
    @buffer.string = ""

    @fragment_id += 1
  end

  def generate_basic
    append_fragment("\\gamename\\ccrenegade\\gamever\\838")
  end

  def generate_info
    append_fragment(
      "\\hostname\\#{ServerConfig.server_name}" \
      "\\hostport\\#{ServerConfig.server_port}" \
      "\\mapname\\#{ServerStatus.get(:current_map)}" \
      "\\gametype\\#{Config.gamespy[:game_type]}" \
      "\\numplayers\\#{ServerStatus.total_players}" \
      "\\maxplayers\\#{ServerStatus.get(:max_players)}"
    )
  end

  def generate_rules
    append_fragment(
      "\\CSVR\\1" \
      "\\DED\\1" \
      "\\password\\#{bool_to_int(ServerStatus.get(:has_password))}" \
      "\\DG\\#{bool_to_int(ServerConfig.driver_gunner)}" \
      "\\TC\\#{bool_to_int(ServerConfig.team_changing)}" \
      "\\FF\\#{bool_to_int(ServerConfig.friendly_fire)}" \
      "\\SC\\#{ServerConfig.starting_credits}" \
      "\\SSC\\Mobius v#{Mobius::VERSION}" \
      "\\timeleft\\#{ServerStatus.get(:time_remaining)}"
    )

    Config.gamespy[:custom_info].each do |key, value|
      append_fragment("\\#{key}\\#{value}")
    end
  end

  def generate_players
    [0, 1].each do |team|
      append_fragment(
        "\\team_t#{team}\\#{Teams.name(team)}" \
        "\\score_t#{team}\\#{ServerStatus.get(:"team_#{team}_points")}"
      )
    end

    PlayerData.player_list.each_with_index do |player, index|
      append_fragment(
        "\\player_#{index}\\#{player.name}" \
        "\\score_#{index}\\#{player.score}" \
        "\\ping_#{index}\\#{player.ping}" \
        "\\team_#{index}\\#{player.team}" \
        "\\kills_#{index}\\#{player.kills}" \
        "\\deaths_#{index}\\#{player.deaths}"
      )
    end
  end
end
