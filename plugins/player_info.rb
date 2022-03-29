class PlayerInfoPlugin < Mobius::Plugin
  def start
  end

  def tick
    # log(self.class, "Requesting player_info via RenRem...")
    # renrem_cmd("player_info")
    # renrem_cmd("game_info")
  end

  def teardown
    log
  end
end