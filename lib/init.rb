module Mobius
  ROOT_PATH = File.expand_path("..", __dir__)

  def self.init
    modules = [
      Config,
      # SSGM,
      RenRem,
      PluginManager
    ]

    modules.each(&:init)

    # TODO: start sane main loop
    loop do
      PluginManager.publish_event(:tick)
      sleep 1
    end


  ensure
    modules.reverse.each(&:teardown)
  end
end
