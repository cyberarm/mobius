module Mobius
  ROOT_PATH = File.expand_path("..", __dir__)

  def self.init
    modules = [
      Config,
      Teams,
      Database,
      RenRem,
      SSGM,
      GameLog,
      RenLog,
      ServerStatus,
      MapSettings,
      PluginManager,
      ModerationServerClient
    ]

    modules.each(&:init)

    log("INIT", "Successfully initialized Mobius v#{Mobius::VERSION}")

    # TODO: start sane main loop

    RenRem.cmd("rehash_ban_list")

    loop do
      while (cmd = RenRem.queue.shift)
        RenRem.cmd(cmd)
      end

      PluginManager.publish_event(:tick)

      sleep 1
    end
  ensure
    modules.reverse.each(&:teardown)
  end
end
