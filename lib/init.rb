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
      # ModerationServerClient
    ]

    modules.each(&:init)

    log("INIT", "Successfully initialized Mobius v#{Mobius::VERSION}")

    # TODO: start sane main loop

    RenRem.cmd("rehash_ban_list")

    last_tick_time = 0.0
    loop do
      while (cmd = RenRem.queue.shift)
        RenRem.cmd(cmd)
      end

      RenRem.instance.drain

      if monotonic_time - last_tick_time >= 1.0
        last_tick_time = monotonic_time

        PluginManager.publish_event(:tick)
      end

      sleep 0.001
    end
  ensure
    modules.reverse.each(&:teardown)
  end
end
