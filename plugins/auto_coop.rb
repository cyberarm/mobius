mobius_plugin(name: "AutoCoop", version: "0.0.1") do
  def configure_bots
    player_count = ServerStatus.get(:team_0_players) + ServerStatus.get(:team_1_players)
    bot_count = player_count * @bot_difficulty
    bot_count = 6 if bot_count.zero?

    # Cannot use botcount with asymmetric botcounts 😭
    # if @current_side == 0
    #   RenRem.cmd("botcount #{player_count + @support_bots} 0")
    #   RenRem.cmd("botcount #{bot_count} 1")
    # else
    #   RenRem.cmd("botcount #{player_count + @support_bots} 1")
    #   RenRem.cmd("botcount #{bot_count} 0")
    # end

    RenRem.cmd("botcount #{bot_count}")

    RenRem.cmd("player_info")

    return bot_count
  end

  def move_players_to_coop_team
    PlayerData.player_list.each do |player|
      RenRem.cmd("team2 #{player.id} #{@current_side}")
    end

    RenRem.cmd("player_info")
  end

  on(:start) do
    @current_side = 0
    @bot_difficulty = 2
    @support_bots = 4

    every(5) do
      move_players_to_coop_team
    end
  end

  on(:map_loaded) do
    @current_side += 1
    @current_side %= 2

    after(5) do
      count = configure_bots

      broadcast_message("[AutoCoop] Starting coop on team #{@current_side} with #{count} bots per team")

      move_players_to_coop_team
    end
  end

  on(:player_joined) do |player|
    count = configure_bots

    message_player(player.name, "[AutoCoop] running coop on team #{@current_side} with #{count} bots per team")
    RenRem.cmd("team2 #{player.id} #{@current_side}")
  end

  on(:player_left) do |player|
    configure_bots
  end
end
