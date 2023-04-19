module Mobius
  ROOT_PATH = File.expand_path("..", __dir__)

  def self.init
    major, minor, _point = RUBY_VERSION.split(".").map(&:to_i)
    raise "Must use Ruby 3.2.0 or newer due to changes to Struct class (Using Ruby #{RUBY_VERSION})" unless major >= 3 && minor >= 2

    modules = [
      Config,
      Teams,
      Database,
      RenRem,
      SSGM,
      Presets,
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
    modules.reverse.each(&:teardown) if modules
  end
end
