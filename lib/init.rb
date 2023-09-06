module Mobius
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

    initial_time = monotonic_time
    last_tick_time = initial_time
    last_think_time = initial_time
    time_before_think = initial_time

    think_delay = 1 / 60.0 # ~16ms

    loop do
      while (cmd = RenRem.queue.shift)
        RenRem.cmd(cmd)
      end

      RenRem.instance.drain

      ### begin THINK
      think_time = monotonic_time - last_think_time
      last_think_time = monotonic_time

      PluginManager.publish_event(:think)

      # Track player 'play time' and sync match stats shadow player
      PlayerData.player_list.each do |player|
        player.time += think_time

        PlayerData.update_match_stats(player)
      end
      ### end THINK

      if monotonic_time - last_tick_time >= 1.0
        last_tick_time = monotonic_time

        PluginManager.publish_event(:tick)
      end

      total_think_time = monotonic_time - time_before_think
      sleep_time = think_delay - total_think_time

      # Sleep is imprecise, loop time was ~28ms when targetting ~16ms on dev machine. Eh, good enough for a bot.
      sleep sleep_time if sleep_time > 0

      time_before_think = monotonic_time
    end
  ensure
    modules.reverse.each(&:teardown) if modules
  end
end
