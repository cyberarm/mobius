mobius_plugin(name: "GameSpy", version: "0.0.1") do
  MasterServer = Struct.new(:socket)

  on(:start) do
    @master_servers = []
    @server_socket = UDPSocket.new
    @query_port = 0000

    after(300) do
      @master_servers.each do |ms|
        send_heartbeat(ms)
      end
    end
  end

  on(:shutdown) do
  end

  def send_heartbeat(master_server)
    master_server.socket.send("\\\\heartbeat\\\\#{@query_port}\\\\gamename\\\\cncrenegade")
  end

  def generate_basic
    "\\\\hostname\\\\#{HOSTNAME}" \
    "\\\\hostport\\\\#{HOSTNAME}" \
    "\\\\mapname\\\\#{HOSTNAME}" \
    "\\\\gametype\\\\#{HOSTNAME}" \
    "\\\\numplayers\\\\#{HOSTNAME}" \
    "\\\\maxplayers\\\\#{HOSTNAME}"
  end

  def generate_rules
    string = "\\\\CSVR\\\\1" \
             "\\\\DED\\\\1" \
             "\\\\password\\\\#{HAS_PASSWORD}" \
             "\\\\DG\\\\#{DRIVER_GUNNER}" \
             "\\\\TC\\\\#{TEAM_CHANGE}" \
             "\\\\FF\\\\#{FRIENDLY_FIRE}" \
             "\\\\SC\\\\#{STARTING_CREDITS}" \
             "\\\\SSC\\\\Mobius v#{Mobius::VERSION}" \
             "\\\\timeleft\\\\#{TIME_LEFT}"

    Config.gamespy[:custom_info].each do |key, value|
      string += "\\\\#{key}\\\\#{value}"
    end

    string
  end

  def generate_players
    fragments = []

    PlayerData.player_list.each_slice(15) do |slice|
      slice.each_with_index do |player, i|
        string = ""
        string += "\\\\player_#{i}\\\\#{player.name}"
        string += "\\\\score_#{i}\\\\#{player.score}"
        string += "\\\\ping_#{i}\\\\#{player.ping}"
        string += "\\\\team_#{i}\\\\#{Teams.id_from_name(player.team)}"
        string += "\\\\kills_#{i}\\\\#{player.value(:stats_kills) || 0}"
        string += "\\\\deaths_#{i}\\\\#{player.value(:stats_deaths) || 0}"

        fragments << string
      end
    end

    [fragments, "\\\\team_t0\\\\#{Teams.name(0)}\\\\score_t0\\\\#{TEAM0_SCORE}\\\\team_t1\\\\#{Teams.name(1)}\\\\score_t0\\\\#{TEAM1_SCORE}"]
  end
end
