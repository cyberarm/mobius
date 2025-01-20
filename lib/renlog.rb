module Mobius
  class RenLog
    include Common

    @@instance = nil

    def self.init
      log("INIT", "Enabling RenLog...")
      new
    end

    def self.teardown
      log("TEARDOWN", "Shutdown RenLog...")
    end

    def self.feed(line)
      # Remove timestamp and convert tabs to spaces

      @@instance&.parse_line(line.split("]", 2).last.strip.gsub(/\t/, " "))
    end

    def initialize
      @@instance = self

      @joiners = []
      @renew_ssgm = false
      @log_player_info = false
      @read_game_defs = false

      ServerConfig.fetch_available_maps
    end

    def parse_line(line)
      # pp [:renlog, line]

      # Skip level loading messages
      return if line.downcase.match?(/^load \d+% complete$/)

      if line.match?(/^(\[Team\]\s)?([^\s:]+):\s(.+)/)
        match_data = line.match(/^(\[Team\]\s)?([^\s:]+):\s(.+)/)

        pp match_data.to_a if Config.debug_verbose

        team_chat = match_data[1]
        username  = match_data[2]
        message   = match_data[3]

        handle_chat(!team_chat.nil?, username, message)
      elsif line.match?(/^\[Page\]\s([^:]+):\s(.+)$/) # Isn't PAGE only for WOL?
        match_data = line.match(/^\[Page\]\s([^:]+):\s(.+)$/)

        username = match_data[1]
        message  = match_data[2]

        handle_page(username, message)
      else
        handle_input(line)
      end

      PluginManager.publish_event(:renlog, line)

      SSGM.data_recorder&.log(:renlog, nil, line)
    end

    def handle_chat(team_chat, username, message)
      pp [:renlog_chat, team_chat, username, message] if Config.debug_verbose

      if username == "Host"
        handle_host_message(message)
      end

      player = PlayerData.player(PlayerData.name_to_id(username))
      return unless player

      # TODO: Detect if player is mod or admin and format their name as such

      if team_chat && true # TODO: Add option for whether team chat is published to IRC
        # TODO: Publish formatted message to IRC
      else
        # TODO: Publish formatted message to IRC
      end

      if message.start_with?("!")
        PluginManager.handle_command(player, message)
      else
        PluginManager.publish_event(
          team_chat ? :team_chat : :chat,
          player,
          message
        )
      end
    end

    def handle_host_message(message)
      if message.match?(/^(.+?) changed teams.$/)
        match_data = message.match(/^(.+?) changed teams.$/)

        username = match_data[1]
        puts "USERNAME: #{username}"

        PluginManager.publish_event(:irc_broadcast, message)
        # PlayerData.player(username).set_value(:changed_team, true)

        RenRem.cmd("game_info")
        RenRem.cmd("pinfo")

      else
        PluginManager.publish_event(:irc_broadcast, message)
      end
    end

    # NO OP?
    def handle_page(username, message)
      pp [:renlog_page, message, username] if Config.debug_verbose
    end

    def handle_input(line)
      pp [:renlog_input, line] if Config.debug_verbose

      return if handle_list_game_defs(line)

      if line.start_with?("The Current Map Number is ")
        match_data = line.match(/The Current Map Number is (\d+)/)
        map_number = match_data[1].to_i

        ServerStatus.update_map_number(map_number)
        return
      end

      if line.match?(/(.+?) mode active/)
        match_data = line.match(/(.+?) mode active/)

        mode = match_data[1]

        ServerStatus.update_mode(mode)
        return
      end

      if line.start_with?("Map : ")
        _, map_name = line.split(":")

        ServerStatus.update_map(map_name.strip)
        return
      end

      if line.start_with?("Time : ")
        _, time = line.split(":")

        ServerStatus.update_time_remaining(time)
        return
      end

      if line.start_with?("Fps : ")
        _, sfps = line.split(":")

        ServerStatus.update_sfps(sfps.to_i)
        return
      end

      team_0_abbrev = Teams.abbreviation(0)
      if line.start_with?("#{team_0_abbrev} : ")
        match_data = line.match(/#{team_0_abbrev} : (.+?)\/(.+?) players\s+ (.+?) points/)

        player_count     = match_data[1].to_i
        max_player_count = match_data[2].to_i
        team_points      = match_data[3].to_i

        ServerStatus.update_team_status(0, player_count, max_player_count, team_points)
        return
      end

      team_1_abbrev = Teams.abbreviation(1)
      if line.start_with?("#{team_1_abbrev} : ")
        match_data = line.match(/#{team_1_abbrev} : (.+?)\/(.+?) players\s+ (.+?) points/)

        player_count     = match_data[1].to_i
        max_player_count = match_data[2].to_i
        team_points      = match_data[3].to_i

        ServerStatus.update_team_status(1, player_count, max_player_count, team_points)
        return
      end

      return if handle_player_info(line)

      return if handle_player_left(line)

      return if handle_player_joined(line)

      return if handle_level_loaded(line)

      return if handle_fds_messages(line)

      return if handle_server_crash(line)

      return if handle_player_scripts_version(line)

      return if handle_server_version(line)

      return if handle_player_bandwidth(line)

      return if handle_bhs_required(line) # TODO: Maybe? IDK what that is...

      return if handle_loading_level(line) # TODO: Don't we already skip these?

      return if handle_vehicle_purchased(line) # NOTE: No OP? This is handled in GameLog atm... 🤔

      return if handle_player_lost_connection(line)

      return if handle_player_was_kicked(line) # TODO
    end

    def handle_list_game_defs(line)
      if @read_game_defs
        if line.empty?
          @read_game_defs = false
        else
          ServerConfig.installed_maps << line
        end

        return true
      end

      if line.start_with?("Available game definitions:")
        @read_game_defs = true
        ServerConfig.installed_maps.clear

        return true
      end
    end

    def handle_player_info(line)
      if line.start_with?("Start PInfo output")
        @log_player_info = true

        return true
      end

      if line.start_with?("End PInfo output")
        @log_player_info = false

        # Check player list for invalid player names
        check_player_list

        PluginManager.publish_event(:player_info_updated)

        return true
      end

      if @log_player_info
        parse_player_info(line)

        return true
      end
    end

    def handle_player_left(line)
      if line =~ /^Player (.+?) left the game$/
        match_data = line.match(/^Player (.+?) left the game$/)

        name = match_data[1]

        player = PlayerData.player(PlayerData.name_to_id(name))

        PluginManager.publish_event(
          :player_left,
          player
        )

        log "PlayerData", "#{player.name} left the game"

        RenRem.cmd("game_info")
        RenRem.cmd("pinfo")

        PlayerData.update_match_stats(player)
        PlayerData.delete(player)

        # TODO: More work needed

        return true
      end
    end

    def handle_player_joined(line)
      if line =~ /^Player (.+?) joined the game$/
        match_data = line.match(/^Player (.+?) joined the game$/)

        name = match_data[1]

        RenRem.cmd("game_info")
        RenRem.cmd("pinfo")

        # TODO: More work needed

        return true
      end
    end

    def parse_player_info(line)
      # i, m_pName, m_Score, m_Team, m_Ping, m_IP, m_KB, m_Rank, m_Kills, m_Deaths, m_Money, m_KD

      split_data = line.split(",")

      id       = split_data[0].to_i
      name     = split_data[1]
      score    = split_data[2].to_i
      team     = split_data[3].to_i
      ping     = split_data[4].to_i
      address  = split_data[5]
      kbps     = split_data[6].to_i
      rank     = split_data[7].to_i
      kills    = split_data[8].to_i
      deaths   = split_data[9].to_i
      money    = split_data[10].to_i
      kd       = split_data[11].to_f
      # time     = split_data[7]

      PlayerData.update(
        origin: :game,
        id: id,
        name: name,
        score: score,
        team: team,
        ping: ping,
        address: address,
        kbps: kbps,
        rank: rank,
        kills: kills,
        deaths: deaths,
        money: money,
        kd: kd,
        last_updated: monotonic_time
      )

      check_username(id, name, address)
    end

    def handle_level_loaded(line)
      if line == "Level loaded OK"
        PluginManager.publish_event(:irc_broadcast, line)
        ServerConfig.read_server_settings

        # "reload" map settings
        MapSettings.new

        MapSettings.apply_map_settings(apply_time: true)

        # ENSURE that the mapnum has been handled **BEFORE** sending :map_loaded event
        RenRem.cmd("mapnum") do |response|
          result = response.to_s.strip

          if result.start_with?("The Current Map Number is ")
            match_data = result.match(/The Current Map Number is (\d+)/)
            map_number = match_data[1].to_i

            ServerStatus.update_map_number(map_number)
          end

          PluginManager.publish_event(
            :map_loaded,
            ServerStatus.get(:current_map)
          )
        end

        # TODO: Auto balance teams, if enabled.

        RenRem.cmd("game_info")
        RenRem.cmd("pinfo")

        return true
      end
    end

    def handle_fds_messages(line)
      case line
      when /^\w+ not found$/,
           "Logging on....",
           /^Logging onto .+ Server$/,
           "Failed to log in",
           "Creating game channel",
           "Channel created OK",
           "Terminating game"

        PluginManager.publish_event(:irc_admin_message, line)

        return true
      end
    end

    def handle_server_crash(line)
      if line =~ /^Initializing .+ Mode$/
        PluginManager.publish_event(:irc_broadcast, line)

        PlayerData.clear
        RenRem.cmd("sversion")
        ServerConfig.fetch_available_maps

        return true
      end
    end

    def handle_player_scripts_version(line)
      if line.match?(/^The version of player (.+?) is (\d+\.\d+)( r\d+)?/)
        match_data = line.match(/^The version of player (.+?) is (\d+\.\d+)( r\d+)?/)

        id               = match_data[1].to_i
        scripts_version  = Float(match_data[2])
        scripts_revision = match_data[3].to_s.strip.empty? ? 1 : Integer(match_data[3].to_s.strip.sub("r", ""))

        if (player = PlayerData.player(id))
          player.set_value(:scripts_version, scripts_version)
          player.set_value(:scripts_reversion, scripts_revision)

          log "#{player.name} has scripts #{scripts_version} (revision: #{scripts_revision})"
        end

        return true
      end
    end

    def handle_server_version(line)
      if line =~ /^The Version of the server is (.+)/ || line =~ /^The version of (?:(?:bhs|tt|bandtest).dll|(?:game|server).exe) on this machine is (\d+\.\d+)( r\d+)?/
        match_data = line.match(/^The Version of the server is (.+)/) if line =~ /^The Version of the server is (.+)/
        match_data ||= line.match(/^The version of (?:(?:bhs|tt|bandtest).dll|(?:game|server).exe) on this machine is (\d+\.\d+)( r\d+)?/)

        ServerConfig.scripts_version  = Float(match_data[1])
        ServerConfig.scripts_revision = match_data[2].to_s.strip.empty? ? 1 : Integer(match_data[2].to_s.strip.sub("r", ""))

        log "The server is running scripts: #{ServerConfig.scripts_version} r#{ServerConfig.scripts_revision}" if Config.debug_verbose

        return true
      end
    end

    def handle_player_bandwidth(line)
      if line =~ /Current Bandwidth for player (.*?) is (.+)/
        match_data = line.match(/Current Bandwidth for player (.*?) is (.+)/)

        name = match_data[1]
        bandwidth = match_data[2].to_i

        if (player = PlayerData.player(PlayerData.name_to_id(name)))
          player.set_value(:bandwidth, bandwidth)
        end
      end
    end

    # NOTE: Remove? Only planning on supporting Scripts/SSGM 4.x+
    def handle_bhs_required(line)
      if line =~ /is required for this map/
        ServerConfig.force_bhs_dll_map = true

        # TODO: Kick players who have been in-game more then 4 seconds and have a scripts version that is to low

        return true
      end
    end

    def handle_loading_level(line)
      if line =~ /Loading level (.+)/
        match_data = line.match(/Loading level (.+)/)
        PluginManager.publish_event(:irc_broadcast, line)

        pp match_data[1] if Config.debug_verbose

        ServerStatus.update_map(match_data[1])
        ServerConfig.force_bhs_dll_map = false # REMOVE?
        # TODO: The last game has completed, process game results

        RenRem.cmd("mapnum")

        if ServerConfig.data[:nextmap_changed_id]
          log "Restoring map at index #{ServerConfig.data[:nextmap_changed_id]} to #{ServerConfig.data[:nextmap_changed_mapname]}"
          RenRem.cmd("mlistc #{ServerConfig.data[:nextmap_changed_id]} #{ServerConfig.data[:nextmap_changed_mapname]}")

          # Update rotation
          ServerConfig.rotation[ServerConfig.data[:nextmap_changed_id]] = ServerConfig.data[:nextmap_changed_mapname]

          ServerConfig.data.delete(:nextmap_changed_id)
          ServerConfig.data.delete(:nextmap_changed_mapname)
        end

        return true
      end
    end

    def handle_vehicle_purchased(line)
      # NOTE: No OP? This is handled in GameLog atm... 🤔
    end

    def handle_player_lost_connection(line)
      return false unless (match_data = line.match(/\AConnection broken to client. (.+)\z/))

      player = PlayerData.player(match_data.to_a[1].to_i)
      broadcast_message("[MOBIUS] #{player&.name || "?"} left the game. Game crashed or ping was too high.", red: 255, green: 127, blue: 0) if Config.messages[:player_lost_connection]

      # NOTE: {player} variable might be nil
      PluginManager.publish_event(:player_lost_connection, player)
      PluginManager.publish_event(:irc_broadcast, "#{player&.name || "?"} left the game. Game crashed or ping was too high.")

      return true
    end

    def handle_player_was_kicked(line)
      return false unless line =~ /was kicked/

      PluginManager.publish_event(:irc_broadcast, line)
    end

    def check_player_list
      PlayerData.player_list.reverse.each do |player|
        if monotonic_time - player.last_updated > 40
          log "Deleting data for player #{player.name} (ID: #{player.id})"
          PlayerData.delete(player)
        end

        RenRem.cmd("kick #{player.id}") if player.banned?
      end
    end

    def check_username(id, name, address)
      if name =~ /(:|\!|\&|\s|\\)/
        RenRem.cmd("kick #{id} Disallowed characters in nickname (:, !, &, \\, and whitespace is not allowed.)")
        broadcast_message("[MOBIUS] #{name} has been kicked by Mobius for having disallowed characters in their name", red: 255, green: 127, blue: 0)

      elsif name.length < 3
        RenRem.cmd("kick #{id} Nickname must be at least 3 characters long.")
        broadcast_message("#{name} has been kicked by Mobius for having too short of a nickname!", red: 255, green: 127, blue: 0)

      elsif name =~ /[\001\002\037]/
        RenRem.cmd("kick #{id} Non-ascii characters detected in nickname.")
        broadcast_message("[MOBIUS] Player has been kicked by Mobius for having non-ascii characters in nickname.", red: 255, green: 127, blue: 0)

      elsif name.length > 30
        RenRem.cmd("kick #{id} Nickname may only be 30 characters long.")
        broadcast_message("#{name} has been kicked by Mobius for having too long of a nickname!", red: 255, green: 127, blue: 0)
      end
    end

    # TODO
    def check_ban_list(player)
    end
  end
end
