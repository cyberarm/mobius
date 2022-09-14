module Mobius
  class ServerStatus
    @data = {}

    @data[:server_mode]         = "WOL"
    @data[:current_map]         = "last round"
    @data[:current_map_number]  = -1
    @data[:map_start_time]      = 0
    @data[:last_map]            = "last round"
    @data[:max_players]         = 0
    @data[:team_0_players]      = 0
    @data[:team_0_points]       = 0
    @data[:team_1_players]      = 0
    @data[:team_1_points]       = 0
    @data[:time_remaining]      = 0
    @data[:sfps]                = 0
    @data[:radar_mode]          = 0

    @data[:last_request_time]   = 0
    @data[:last_response_time]  = 0
    @data[:fds_responding]      = true

    @data[:default_max_players] = 0
    @data[:has_password]        = false
    @data[:start_map]           = "N/A"

    @data[:update_interval] = 30.0 # seconds

    def self.get(key)
      @data.fetch(key)
    end

    def self.init
      log "INIT", "Enabling ServerStatus..."
      monitor
    end

    def self.teardown
      log "TEARDOWN", "Shutdown ServerStatus..."
      @monitor_thread&.kill
    end

    def self.monitor
      # Starting game status refresh thread...

      @monitor_thread = Thread.new do
        loop do
          probe_fds

          sleep @data[:update_interval]
        end
      end
    end

    def self.probe_fds
      if @data[:last_response_time] < @data[:last_request_time] - @data[:update_interval] && @data[:fds_responding]
        # ISSUE warning to IRC/mod tool
        @data[:fds_responding] = false

      elsif @data[:last_response_time] > @data[:last_request_time] && !@data[:fds_responding]
        # Connection to FDS restored
        # ISSUE notice to IRC/mod tool

        @data[:fds_responding] = true

        RenRem.cmd("mapnum")
        RenRem.cmd("sversion")
        ServerConfig.fetch_available_maps
      end

      @data[:last_request_time] = Time.now.to_i # FIXME: Use monotonic time!

      RenRem.cmd("mapnum") if @data[:current_map_number] == -1

      RenRem.cmd("sversion")

      RenRem.cmd("pinfo")
      RenRem.cmd("game_info")
    end

    def self.update_mode(mode)
      case mode.downcase.strip
      when /westwood/
        @data[:server_mode] = "WOL"
      when /gamespy/
        @data[:server_mode] = "GSA"
      else
        # TODO: Warn about invalid mode?
      end

      @data[:last_response_time] = Time.now.to_i
    end

    def self.update_radar_mode(mode)
      @data[:radar_mode] = mode
    end

    def self.update_map(map_name)
      @data[:last_response_time] = Time.now.to_i

      return if @data[:current_map] == map_name

      @data[:last_map] = @current_map
      @data[:current_map] = map_name

      @data[:map_start_time] = Time.now.to_i

      # TODO: Only apply map settings if we just loaded otherwise let the level Loaded ok event process it
      # Modules.apply_map_settings(0)
    end

    def self.update_map_number(number)
      @data[:current_map_number] = number

      @data[:last_response_time] = Time.now.to_i
    end

    def self.update_time_remaining(remaining)
      @data[:time_remaining] = remaining.strip

      @data[:last_response_time] = Time.now.to_i
    end

    def self.update_sfps(sfps)
      @data[:sfps] = sfps

      @data[:last_response_time] = Time.now.to_i
    end

    def self.update_team_status(team, player_count, max_player_count, points)
      @data[:"team_#{team}_players"] = player_count
      @data[:max_players] = max_player_count
      @data[:"team_#{team}_points"] = points

      @data[:last_response_time] = Time.now.to_i
    end

    def self.update_default_max_players(max_players)
      @data[:default_max_players] = max_players
    end

    def self.update_has_password(bool)
      @data[:has_password] = bool
    end

    def self.update_start_map(start_map)
      @data[:start_map] = start_map
    end

    def self.game_status
      [
        @data[:server_mode],
        @data[:current_map],
        @data[:team_0_players],
        @data[:team_0_points],
        @data[:team_1_players],
        @data[:team_1_points],
        @data[:total_players],
        @data[:max_players],
        @data[:time_remaining],
        @data[:sfps]
      ]
    end

    def self.total_players
      @data[:team_0_players] + @data[:team_1_players]
    end
  end
end
