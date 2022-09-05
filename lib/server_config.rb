module Mobius
  class ServerConfig
    @data = {}
    @installed_maps = []
    @rotation = []

    def self.data
      @data
    end

    def self.fetch_available_maps
      RenRem.cmd("listgamedefs", 2)
    end

    def self.installed_maps
      @installed_maps
    end

    def self.rotation
      @rotation
    end

    def self.scripts_version
      @data[:scripts_version]
    end

    def self.scripts_version=(string)
      @data[:scripts_version] = string
    end

    def self.scripts_revision
      @data[:scripts_revision]
    end

    def self.scripts_revision=(string)
      @data[:scripts_revision] = string
    end

    def self.force_bhs_dll_map
      @data[:force_bhs_dll_map]
    end

    # No Op?
    def self.force_bhs_dll_map=(bool)
      @data[:force_bhs_dll_map] = bool
    end

    def self.server_name
      @data[:server_name]
    end

    def self.driver_gunner
      @data[:driver_gunner]
    end

    def self.friendly_fire
      @data[:friendly_fire]
    end

    def self.team_changing
      @data[:team_changing]
    end

    def self.starting_credits
      @data[:starting_credits]
    end

    def self.renrem_port
      @data[:renrem_port]
    end

    def self.renrem_password
      @data[:renrem_password]
    end

    def self.ssgm_port
      @data[:ssgm_port]
    end

    def self.read_server_config
      @data[:driver_gunner]    = false
      @data[:friendly_fire]    = false
      @data[:team_changing]    = false
      @data[:starting_credits] = false

      File.open("#{Config.fds_path}/server.ini") do |f|
        f.each_line do |line|
          line = line.strip

          next if line.length.zero? || line.start_with?(";") || line.start_with?("[")

          key, value = line.split("=")
          key = key.strip
          value = value.to_s.strip

          case key
          when "AllowRemoteAdmin"
            unless value == "true" || value == "1"
              log "ServerConfig", "WARNING: AllowRemoteAdmin option in server.ini is not set to true. Mobius will not be able to communicate properly with the server!"
            end
          when "RemoteAdminPassword"
            @data[:renrem_password] = value
          when "RemoteAdminPort"
            @data[:renrem_port] = Integer(value)
          when "Port"
            @data[:server_port] = Integer(value)
          end
        end
      end
    end

    def self.read_server_settings
      @data[:driver_gunner]    = false
      @data[:friendly_fire]    = false
      @data[:team_changing]    = false
      @data[:starting_credits] = false

      File.open("#{Config.fds_path}/#{Config.server_settings_path}") do |f|
        f.each_line do |line|
          line = line.strip

          next if line.length.zero? || line.start_with?(";") || line.start_with?("[")

          key, value = line.split("=")

          key = key.strip
          value = value.to_s.strip

          case key
          when "bGameTitle"
            @data[:server_name] = value
          when "MaxPlayers"
            ServerStatus.update_default_max_players(Integer(value))
          when "IsPassworded"
            ServerStatus.update_has_password(value.downcase == "yes")
          when "TimeLimitMinutes"
            @data[:time_limit] = Integer(value)
          when "DriverIsAlwaysGunner"
            @data[:driver_gunner] = value.downcase == "yes"
          when "IsFriendlyFirePermitted"
            @data[:friendly_fire] = value.downcase == "yes"
          when "IsTeamChangingAllowed"
            @data[:team_changing] = value.downcase == "yes"
          when "StartingCredits"
            @data[:starting_credits] = Integer(value)
          when "RadarMode"
            ServerStatus.update_radar_mode(Integer(value))
          end
        end
      end
    end

    def self.read_ssgm_settings
      File.open("#{Config.fds_path}/ssgm.ini") do |f|
        f.each_line do |line|
          line = line.strip

          next if line.length.zero? || line.start_with?(";") || line.start_with?("[")

          key, value = line.split("=")
          key = key.strip
          value = value.to_s.strip

          case key
          when "Port"
            @data[:ssgm_port] = Integer(value)
          end
        end
      end
    end
  end
end
