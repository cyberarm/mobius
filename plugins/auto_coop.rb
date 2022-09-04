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
      @current_side = 1 # Force players to Allied team as that is how the map is designed
    end
  end

  def check_votes(silent:)
    missing = []

    return if PlayerData.player_list.count.zero?

    PlayerData.player_list.each do |player|
      next if @coop_votes[player.name]

      missing << player
    end

    if missing.size.zero?
      @coop_started = true

      count = configure_bots
      move_players_to_coop_team

      broadcast_message("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team") unless silent
      log("Coop has started by player vote") unless silent
    else
      broadcast_message("[AutoCoop] Still need #{missing.count} to vote!") unless silent
    end
  end

  on(:start) do
    @current_side = 0
    @bot_difficulty = 2
    @support_bots = 4
    @last_bot_count = -1

    @coop_started = false
    @manual_bot_count = false
    @coop_votes = {}

    every(5) do
      if @coop_started
        configure_bots
        move_players_to_coop_team
      else
        check_votes(silent: true)
      end
    end
  end

  on(:map_loaded) do |map|
    @current_side += 1
    @current_side %= 2

    @coop_votes.clear

    check_map(map)

    after(5) do
      if PlayerData.player_list.size.positive?
        @coop_started = true

        count = configure_bots

        log("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")
        broadcast_message("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")

        move_players_to_coop_team
      else
        log("No one is in game after 5 seconds, disabling coop this round.")

        @coop_started = false
      end
    end
  end

  on(:player_joined) do |player|
    if @coop_started
      count = configure_bots

      message_player(player.name, "[AutoCoop] Running coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")
      RenRem.cmd("team2 #{player.id} #{@current_side}")
    else
      broadcast_message("[AutoCoop] Coop will automatically begin on the next map.")
      broadcast_message("[AutoCoop] Vote to start now with !request_coop, 100% of players must request it.")
    end
  end

  on(:player_left) do |player|
    configure_bots

    @coop_votes.delete(player.name)
  end

  command(:request_coop, arguments: 0, help: "!request_coop") do |command|
    if @coop_started
      page_player(command.issuer.name, "Coop is already active!")
    else
      @coop_votes[command.issuer.name] = true
      check_votes(silent: false)
    end
  end

  command(:coop, arguments: 1, help: "!coop <team>", groups: [:admin, :mod, :director]) do |command|
    team = command.arguments.first

    begin
      team = Integer(team)
    rescue ArgumentError
      team = Teams.id_from_name(team)
      team = team[:id] if team
    end

    if team.is_a?(Integer)
      @current_side = team
      @coop_started = true

      count = configure_bots
      move_players_to_coop_team

      broadcast_message("[AutoCoop] #{command.issuer.name} has started coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")
    else
      page_player(command.issuer.name, "[AutoCoop] Failed to detect team for: #{command.arguments.first}, got #{team}, try again.")
    end
  end
end
