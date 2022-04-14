module Mobius
  class RenLog
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
    end

    def parse_line(line)
      # pp [:renlog, line]

      # Skip level loading messages
      return if line.downcase.match?(/^load \d+% complete$/)

      if line.match?(/^(\[Team\]\s)?([^\s:]+):\s(.+)/)
        match_data = line.match(/^(\[Team\]\s)?([^\s:]+):\s(.+)/)

        pp match_data.to_a

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
    end

    def handle_chat(team_chat, username, message)
      pp [:renlog_chat, team_chat, username, message]

      if username == "Host"
        handle_host_message(message)

        return
      end

      player = PlayerData.player(username, true)
      return unless player

      # TODO: Detect if player is mod or admin and format their name as such

      if team_chat && true # TODO: Add option for whether team chat is published to IRC
        # TODO: Publish formatted message to IRC
      else
        # TODO: Publish formatted message to IRC
      end

      if message.start_with?("!")
        # TODO: Handle Command
      end

      # TODO: Send message to subscribed plugins
    end

    def handle_host_message(message)
      if message.match?(/^(.+?) changed teams.$/)
        match_data = message.match(/^(.+?) changed teams.$/)

        username = match_data[1]

        # TODO: Deliver message to IRC/mod tool
        # PlayerData.player(username).set_value(:changed_team, true)

        # RenRem.cmd("game_info")
        # RenRem.cmd("player_info")
      else
        # TODO: Deliver message to IRC/mod tool
      end
    end

    # NO OP?
    def handle_page(username, message)
      pp [:renlog_page, message, username]
    end

    def handle_input(line)
      pp [:renlog_input, line]

      return if handle_list_game_defs(line)

      if line.start_with?("The Current Map Number is ")
        match_data = line.match(/The Current Map Number is (\d+)/)
        map_number = match_data[1]

        # TODO: Set server status map number
        return
      end

      if line.match?(/(.+?) mode active/)
        match_data = line.match(/(.+?) mode active/)

        mode = match_data[1]
        # TODO: Set server status mode
        return
      end

      if line.start_with?("Map : ")
        _, map_name = line.split(":")

        # TODO: Set server status map
        return
      end

      if line.start_with?("Map : ")
        _, map_name = line.split(":")

        # TODO: Set server status map
        return
      end

      if line.start_with?("Time : ")
        _, time = line.split(":")

        # TODO: Set server status time
        return
      end

      if line.start_with?("Fps : ")
        _, sfps = line.split(":")

        # TODO: Set server status sfps
        return
      end

      # FIXME: Get actual team abbrev from Teams helper class
      team_0_abbrev = "Sov"
      if line.start_with?("#{team_0_abbrev} : ")
        match_data = line.match(/#{team_0_abbrev} : (.+?)\/(.+?) players\s+ (.+?) points/)

        player_count     = match_data[1]
        max_player_count = match_data[2]
        team_points      = match_data[3]

        # TODO: Set team zero's status
        return
      end

      # FIXME: Get actual team abbrev from Teams helper class
      team_1_abbrev = "All"
      if line.start_with?("#{team_1_abbrev} : ")
        match_data = line.match(/#{team_1_abbrev} : (.+?)\/(.+?) players\s+ (.+?) points/)

        player_count     = match_data[1]
        max_player_count = match_data[2]
        team_points      = match_data[3]

        # TODO: Set team ones's status
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

      return if handle_player_bandwidth(line) # TODO

      return if handle_bhs_required(line) # TODO: Maybe? IDK what that is...

      return if handle_loading_level(line) # TODO: Don't we already skip these?

      return if handle_vehicle_purchased(line) # TODO

      return if handle_player_lost_connection(line) # TODO

      return if handle_player_was_kicked(line) # TODO
    end

    def handle_list_game_defs(line)
      if @read_game_defs
        if line.empty?
          @read_game_defs = false
        else
          # TODO: Add to list of maps
        end

        return true
      end

      if line.start_with?("Available game definitions:")
        @read_game_defs = true
        # TODO: Clear list of maps

        return true
      end
    end

    def handle_player_info(line)
      if line =~ /Id\s+Name/
        @log_player_info = true

        return true
      end

      if line =~ /No players/
        @log_player_info = false

        return true
      end

      if line =~ /Total current bandwidth/
        @log_player_info = false

        # TODO: Check player list for kicked or invalid player names

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

        username = match_data[1]

        # player = PlayerData.player(username)

        # TODO: More work needed

        return true
      end
    end

    def handle_player_joined(line)
      if line =~ /^Player (.+?) joined the game$/
        match_data = line.match(/^Player (.+?) joined the game$/)

        username = match_data[1]

        # player = PlayerData.player(username)

        # TODO: More work needed

        return true
      end
    end

    def parse_player_info(line)
      split_data = line.split(" ")

      id       = split_data[0].to_i
      username = split_data[1]
      score    = split_data[2].to_i
      side     = split_data[3]
      ping     = split_data[4].to_i
      address  = split_data[5]
      kbits    = split_data[6].to_i
      time     = split_data[7]

      # TODO: Update player data
    end

    def handle_level_loaded(line)
      if line == "Level loaded OK"
        # TODO: Send message to IRC/mod tool
        # TODO: Read/update server settings
        # TODO: Apply map rules (without setting map time?)

        # TODO: Publish :map_changed/:map_load event for to plugins

        # TODO: Auto balance teams, if enabled.

        RenRem.cmd("game_info")
        RenRem.cmd("player_info")

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
        # TODO: Send message to admin channel of IRC/mod tool

        return true
      end
    end

    def handle_server_crash(line)
      if line =~ /^Initializing .+ Mode$/
        # TODO: Send message to IRC/mod tool
        # PlayerData.clear
        RenRem.cmd("sversion")
        # Config.get_available_maps

        return true
      end
    end

    def handle_player_scripts_version(line)
      if line.match?(/^The version of player (.+?) is (\d+\.\d+)( r%d+)?/)
        match_data = line.match(/^The version of player (.+?) is (\d+\.\d+)( r%d+)?/)

        username         = match_data[1]
        scripts_version  = match_data[2]
        scripts_revision = match_data[3]

        log "#{username} has scripts #{scripts_version} (revision: #{scripts_revision})"

        return true
      end
    end

    def handle_server_version(line)
      if line =~ /^The Version of the server is (.+)/ || line =~ /^The version of (?:(?:bhs|tt|bandtest).dll|(?:game|server).exe) on this machine is (\d+\.\d+)( r\d+)?/
        match_data = line.match(/^The Version of the server is (.+)/) if line =~ /^The Version of the server is (.+)/
        match_data ||= line.match(/^The version of (?:(?:bhs|tt|bandtest).dll|(?:game|server).exe) on this machine is (\d+\.\d+)( r\d+)?/)

        # Config.server_scripts_version  = match_data[1]
        # Config.server_scripts_revision = match_data[2].strip

        return true
      end
    end

    def handle_player_bandwidth(line)
    end

    # NOTE: Remove? Only planning on supporting Scripts/SSGM 4.x+
    def handle_bhs_required(line)
      if line =~ /is required for this map/
        # Config.force_bhs_dll_map = true

        # TODO: Kick players who have been in-game more then 4 seconds and have a scripts version that is to low

        return true
      end
    end

    def handle_loading_level(line)
      if line =~ /Loading level (.+)/
        # Send message to IRC/mod tool
        # TODO: Update server status map
        # TODO: reset Config.force_bhs_dll_map to false # REMOVE?
        # TODO: The last game has completed, process game results

        return true
      end
    end

    def handle_vehicle_purchased(line)
    end

    def handle_player_lost_connection(line)
    end

    def handle_player_was_kicked(line)
    end
  end
end
