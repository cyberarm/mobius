module Mobius
  class Config
    @@instance = nil

    def self.init(path: nil)
      log("INIT", "Loading Config...")

      path ? new(path: path) : new
    end

    def self.teardown
    end

    def self.method_missing(*args)
      if args.count == 1
        raise "Config not loaded!" unless @@instance

        @@instance.send(args[0])
      else
        raise "No setters permitted from global namespace."
      end
    end

    attr_reader :fds_path, :server_settings_path, :database_path, :banlist_path, :remix_teams_by_skill, :renrem_address, :renrem_port, :renrem_password,
                :ssgm_address, :ssgm_port, :gamespy, :staff, :debug_verbose, :messages, :limit_commands_to_staff_level,
                :record_gamelog, :discord_bot, :discord_bridge, :tournament, :enabled_plugins, :disabled_plugins

    def initialize(path: "#{ROOT_PATH}/conf/config.json")
      @@instance = self
      @path = path

      reload_config(reload: false)
    end

    def reload_config(reload: true)
      @data = JSON.parse(File.read(@path), symbolize_names: true)

      @fds_path = @data.dig(:mobius, :fds_path)
      @server_settings_path = @data.dig(:mobius, :server_settings_path)
      @database_path = @data.dig(:mobius, :database_path)
      @banlist_path = @data.dig(:mobius, :banlist_path)
      @remix_teams_by_skill = @data.dig(:mobius, :remix_teams_by_skill)

      ServerConfig.read_server_config
      ServerConfig.read_server_settings
      ServerConfig.read_ssgm_settings

      @renrem_address = "127.0.0.1"
      @renrem_port = ServerConfig.renrem_port
      @renrem_password = ServerConfig.renrem_password

      @ssgm_address = "127.0.0.1"
      @ssgm_port = ServerConfig.ssgm_port

      @gamespy = @data.dig(:mobius, :gamespy)

      @staff = @data.dig(:mobius, :staff)

      @debug_verbose = false

      @messages = @data.dig(:mobius, :messages) || {}

      @limit_commands_to_staff_level = @data.dig(:mobius, :limit_commands_to_staff_level) || nil

      @record_gamelog = @data.dig(:mobius, :record_gamelog) || false

      @discord_bot = @data.dig(:mobius, :discord_bot)

      @discord_bridge = @data.dig(:mobius, :discord_bridge)

      @tournament = @data.dig(:mobius, :tournament) || {
        team_0_ghost_preset: "Allied_Ghost",
        team_1_ghost_preset: "Soviet_Ghost",
        infected_preset: "Ant_Scout"
      }

      @enabled_plugins = @data.dig(:mobius, :enabled_plugins)
      @disabled_plugins = @data.dig(:mobius, :disabled_plugins)

      PluginManager.publish_event(:config_reloaded) if reload
    end
  end
end
