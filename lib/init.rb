module Mobius
  ROOT_PATH = File.expand_path("..", __dir__)

  def self.init
    modules = [
      Config,
      RenRem,
      SSGM,
      GameLog,
      RenLog,
      ServerStatus,
      PluginManager
    ]

    modules.each(&:init)

    log("INIT", "Successfully initialized Mobius v#{Mobius::VERSION}")

    # TODO: start sane main loop
    loop do
      PluginManager.publish_event(:tick)
      sleep 1
    end


  ensure
    modules.reverse.each(&:teardown)
  end
end
