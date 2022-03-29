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

    attr_reader :renrem_address, :renrem_port, :renrem_password, :ssgm_address, :ssgm_port

    def initialize(path: "#{ROOT_PATH}/conf/config.json")
      @@instance = self

      @data = JSON.parse(File.read(path), symbolize_names: true)

      @renrem_address = @data.dig(:mobius, :renrem, :address)
      @renrem_port = @data.dig(:mobius, :renrem, :port)
      @renrem_password = @data.dig(:mobius, :renrem, :password)

      @ssgm_address = @data.dig(:mobius, :ssgm, :address)
      @ssgm_port = @data.dig(:mobius, :ssgm, :port)
    end
  end
end
