mobius_plugin(name: "AutoCoop", version: "0.0.1") do
  def configure_bots
    player_count = ServerStatus.get(:team_0_players) + ServerStatus.get(:team_1_players)
    base_bot_count = 12
    bot_count = player_count * @bot_difficulty
    bot_count = base_bot_count if bot_count.zero? || bot_count < base_bot_count

    # Cannot use botcount with asymmetric bot count 😭
    # if @current_side == 0
    #   RenRem.cmd("botcount #{player_count + @support_bots} 0")
    #   RenRem.cmd("botcount #{bot_count} 1")
    # else
    #   RenRem.cmd("botcount #{player_count + @support_bots} 1")
    #   RenRem.cmd("botcount #{bot_count} 0")
    # end

    return bot_count unless @last_bot_count != bot_count

    if PlayerData.player_list.count > base_bot_count
      if @current_side == 0
        RenRem.cmd("botcount 0 0")
        RenRem.cmd("botcount #{bot_count} 1")
      else
        RenRem.cmd("botcount 0 1")
        RenRem.cmd("botcount #{bot_count} 0")
      end
    else
      RenRem.cmd("botcount #{bot_count}")
    end

    RenRem.cmd("player_info")

    @last_bot_count = bot_count

    return bot_count
  end

  def move_players_to_coop_team
    return unless PlayerData.player_list.size.positive?

    PlayerData.player_list.each do |player|
      next unless Teams.id_from_name(player.team) != @current_side

      RenRem.cmd("team2 #{player.id} #{@current_side}")
    end

    RenRem.cmd("player_info")
  end

  def check_map(map)
    case map
    when "RA_AS_Seamist", "RA_AS_Seamist.mix"
      @current_side = 1
    end
  end

  on(:start) do
    @current_side = 0
    @bot_difficulty = 2
    @support_bots = 4
    @last_bot_count = -1

    @coop_started = false

    every(5) do
      if @coop_started
        configure_bots
        move_players_to_coop_team
      end
    end
  end

  on(:map_loaded) do |map|
    @current_side += 1
    @current_side %= 2

    check_map(map)

    after(5) do
      if PlayerData.player_list.size.positive?
        @coop_started = true

        count = configure_bots

        broadcast_message("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")

        move_players_to_coop_team
      else
        @coop_started = false
      end
    end
  end

  on(:player_joined) do |player|
    count = configure_bots

    message_player(player.name, "[AutoCoop] running coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")
    RenRem.cmd("team2 #{player.id} #{@current_side}")
  end

  on(:player_left) do |player|
    configure_bots
  end
end
