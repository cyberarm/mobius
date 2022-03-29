class PlayerInfoPlugin < Mobius::Plugin
  def start
    renrem_cmd("player_info")
  end

  def tick
  end

  def teardown
    log
  end
end