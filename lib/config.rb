module Mobius
  class Config
    @@instance = nil

    def self.init(path: nil)
      Mobius.log("INIT", "Loading Config...")

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
                :ssgm_address, :ssgm_port, :staff, :debug_verbose, :messages, :limit_commands_to_staff_level,
                :record_gamelog, :enabled_plugins, :disabled_plugins

    def initialize(path: "#{ROOT_PATH}/conf/config.json")
      @@instance = self
      @path = path

      reload_config(reload: false)
    end

    def reload_config(reload: true)
      @data = JSON.parse(File.read(@path), symbolize_names: true)

      @fds_path = @data[:fds_path]
      @server_settings_path = @data[:server_settings_path]
      @database_path = @data[:database_path]
      @banlist_path = @data[:banlist_path]
      raise "'banlist_path' is not specified in config!" unless @banlist_path
      @remix_teams_by_skill = @data[:remix_teams_by_skill]

      ServerConfig.read_server_config
      ServerConfig.read_server_settings
      ServerConfig.read_ssgm_settings

      @renrem_address = "127.0.0.1"
      @renrem_port = ServerConfig.renrem_port
      @renrem_password = ServerConfig.renrem_password

      @ssgm_address = "127.0.0.1"
      @ssgm_port = ServerConfig.ssgm_port

      @staff = @data[:staff]

      @debug_verbose = false

      @messages = @data[:messages] || {}

      @limit_commands_to_staff_level = @data[:limit_commands_to_staff_level] || nil

      @record_gamelog = @data[:record_gamelog] || false

      @enabled_plugins = @data[:enabled_plugins]
      @disabled_plugins = @data[:disabled_plugins]

      MapSettings.new

      PluginManager.publish_event(:config_reloaded) if reload
    end
  end
end
