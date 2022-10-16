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

    attr_reader :fds_path, :server_settings_path, :database_path, :renrem_address, :renrem_port, :renrem_password, :ssgm_address, :ssgm_port, :gamespy, :staff, :debug_verbose, :gamelog_messages

    def initialize(path: "#{ROOT_PATH}/conf/config.json")
      @@instance = self

      @data = JSON.parse(File.read(path), symbolize_names: true)

      @fds_path = @data.dig(:mobius, :fds_path)
      @server_settings_path = @data.dig(:mobius, :server_settings_path)
      @database_path = @data.dig(:mobius, :database_path)

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

      @gamelog_messages = @data.dig(:mobius, :gamelog_messages)
    end
  end
end
