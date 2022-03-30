class PlayerInfoPlugin < Mobius::Plugin
  def start
  end

  def tick
    @last_time ||= Time.new(2000)
    return unless Time.now - @last_time >= 10

    # log(self.class, "Requesting data via RenRem...")
    # renrem_cmd("game_info")
    # renrem_cmd("player_info")
    # renrem_cmd("listgamedefs")
    # renrem_cmd("quit")
    # renrem_cmd("mapnum")
    # renrem_cmd("sversion")
    # renrem_cmd("version #{id}")
    # renrem_cmd("help")
    # renrem_cmd("botcount 32")

    @last_time = Time.now
  end

  def teardown
    log(self.class, "Shutting down.")
  end
end
