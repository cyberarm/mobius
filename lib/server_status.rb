class Mobius
  class ServerStatus
    attr_reader :server_mode, :current_map, :current_map_number, :map_start_time, :last_map, :max_players,
                :team_0_players, :team_0_points, :team_1_players, :team_1_points, :time_remaining, :sfps, :radar_mode,
                :default_max_players, :has_password, :start_map

    def initialize
      @server_mode         = "WOL"
      @current_map         = "last round"
      @current_map_number  = -1
      @map_start_time      = 0
      @last_map            = "last round"
      @max_players         = 0
      @team_0_players      = 0
      @team_0_points       = 0
      @team_1_players      = 0
      @team_1_points       = 0
      @time_remaining      = 0
      @sfps                = 0
      @radar_mode          = 0

      @last_request_time   = 0
      @last_response_time  = 0
      @fds_responding      = true

      @default_max_players = 0
      @has_password        = false
      @start_map           = "N/A"

      @update_interval = 30.0 # seconds

      monitor
    end

    def monitor
      # Starting game status refresh thread...

      Thread.new do
        loop do
          probe_fds

          sleep @update_interval
        end
      end
    end

    def probe_fds
      if @last_response_time < @last_request_time - @update_interval && @fds_responding
        # ISSUE warning to IRC/mod tool
        @fds_responding = false
      elsif @last_response_time > @last_request_time && !@fds_responding
        # Connection to FDS restored
        # ISSUE notice to IRC/mod tool

        @fds_responding = true

        RenRem.cmd("mapnum")
        RenRem.cmd("sversion")

        # TODO: get available maps
        # Config.get_available_maps
      end

      @last_request_time = Time.now # FIXME: Use monotonic time!

      RenRem.cmd("mapnum") if @current_map_number == -1

      # TODO: handle receiving server scripts version
      RenRem.cmd("sversion")

      RenRem.cmd("player_info")
      RenRem.cmd("game_info")
    end

    def update_mode(mode)
      case mode.downcase.strip
      when /westwood/
        @server_mode = "WOL"
      when /gamespy/
        @server_mode = "GSA"
      else
        # TODO: Warn about invalid mode?
      end

      @last_response_time = Time.now
    end

    def update_radar_mode(mode)
      @radar_mode = mode
    end

    def update_map(map_name)
      @last_response_time = Time.now

      return if @current_map == map_name

      @last_map = @current_map
      @current_map = map_name
      @map_start_time = Time.now

      # TODO: Only apply map settings if we just loaded otherwise let the level Loaded ok event process it
      # Modules.apply_map_settings(0)
    end

    def update_map_number(number)
      @current_map_number = number
      @last_response_time = Time.now
    end

    def update_time_remaining(remaining)
      @time_remaining = remaining
      @last_response_time = Time.now
    end

    def update_sfps(sfps)
      @sfps = sfps
      @last_response_time = Time.now
    end

    def update_team_status(team, players, points, max_players)
      instance_variable_set(:"@team_#{team}_players", players)
      instance_variable_set(:"@team_#{team}_points", points)
      @max_players = max_players
      @last_response_time = Time.now
    end

    def update_default_map_players(max_players)
      @default_max_players = max_players
    end

    def update_has_password(bool)
      @has_password = bool
    end

    def update_start_map(start_map)
      @start_map = start_map
    end

    def game_status
      [
        @server_mode,
        @current_map,
        @team_0_players,
        @team_0_points,
        @team_1_players,
        @team_1_points,
        total_players,
        @max_players,
        @time_remaining,
        @sfps
      ]
    end

    def total_players
      @team_0_players + team_1_players
    end
  end
end
