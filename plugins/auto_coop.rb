mobius_plugin(name: "AutoCoop", version: "0.0.1") do
  def configure_bots
    player_count = ServerStatus.total_players
    bot_count = player_count * @bot_difficulty
    bot_count = @base_bot_count if bot_count.zero? || bot_count < @base_bot_count

    bot_count = @max_bot_count if bot_count > @max_bot_count

    # Cannot use botcount with asymmetric bot count 😭
    # if @current_side == 0
    #   RenRem.cmd("botcount #{player_count + @support_bots} 0")
    #   RenRem.cmd("botcount #{bot_count} 1")
    # else
    #   RenRem.cmd("botcount #{player_count + @support_bots} 1")
    #   RenRem.cmd("botcount #{bot_count} 0")
    # end

    if player_count > @friendless_player_count
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

    @last_bot_count = bot_count

    return bot_count
  end

  def move_players_to_coop_team
    return unless ServerStatus.total_players.positive?

    PlayerData.player_list.each do |player|
      next unless player.team != @current_side

      RenRem.cmd("team2 #{player.id} #{@current_side}")
    end

    RenRem.cmd("pinfo")
  end

  def check_map(map)
    case map.split(".", 2).first
    when "RA_AS_Seamist"
      @override_current_side = @current_side
      @current_side = 1 # Force players to Allied team as that is how the map is designed
    when "RA_Volcano", "RA_RidgeWar", "RA_GuardDuty"
      @override_current_side = @current_side
      @current_side = 0 # Force players to Soviet team for aircraft maps
    when "RA_PacificThreat"
      # TODO: Murder ship yard and sub pen on map start
      # RESOLVED: This is done in SSGM.ini
    end
  end

  def check_votes(silent:)
    missing = []

    return if ServerStatus.total_players.zero?

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

  def bot_report

  end

  on(:start) do
    @current_side = 0
    @bot_difficulty = 2
    @support_bots = 4
    @last_bot_count = -1
    @friendless_player_count = 12
    @max_bot_count = 64
    @hardcap_bot_count = 64
    @hardcap_friendless_player_count = 12
    @base_bot_count = 12

    @coop_started = false
    @manual_bot_count = false
    @coop_votes = {}

    # Attempt to auto resume coop if bot is restarted
    # NOTE: Probably won't work if a player is a spy
    after(3) do
      team_0 = ServerStatus.get(:team_0_players)
      team_1 = ServerStatus.get(:team_1_players)

      if team_0 > 1 && team_1.zero?
        @coop_started = true
        @current_side = 0

        broadcast_message("[AutoCoop] Resumed coop on team #{Teams.name(@current_side)}")
      elsif team_1 > 1 && team_0.zero?
        @coop_started = true
        @current_side = 1

        broadcast_message("[AutoCoop] Resumed coop on team #{Teams.name(@current_side)}")
      end
    end

    every(5) do
      if @coop_started
        configure_bots
        move_players_to_coop_team
      else
        check_votes(silent: true)
      end
    end

    every(30) do
      unless @coop_started
        broadcast_message("[AutoCoop] Coop will automatically begin on the next map.")
        broadcast_message("[AutoCoop] Vote to start now on team #{Teams.name(@current_side)} with !request_coop, 100% of players must request it.")
      end
    end
  end

  on(:map_loaded) do |map|
    @current_side += 1
    @current_side %= 2

    @coop_votes.clear

    if @override_current_side
      @current_side = @override_current_side

      log "Restored coop team to #{Teams.name(@current_side)}, was overridden by map rule."

      @override_current_side = nil
    end

    check_map(map)

    after(5) do
      if ServerStatus.total_players.positive?
        @coop_started = true

        count = configure_bots

        log("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")
        broadcast_message("[AutoCoop] Starting coop on team #{Teams.name(@current_side)} with #{count / 2} bots per team")

        move_players_to_coop_team
      else
        log("No one is in game after 5 seconds, disabling coop this round.")

        RenRem.cmd("botcount 0")
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
      broadcast_message("[AutoCoop] Vote to start now on team #{Teams.name(@current_side)} with !request_coop, 100% of players must request it.")
    end
  end

  on(:player_left) do |player|
    configure_bots

    @coop_votes.delete(player.name)
  end

  command(:botcount, arguments: 0, help: "Reports number of bots configured") do |command|
    broadcast_message("[AutoCoop] There are #{@last_bot_count / 2} bots per team")
  end

  command(:bot_diff, arguments: 0, help: "Reports bot difficulty (bots per player)") do |command|
    broadcast_message("[AutoCoop] Bot difficulty is set to #{@bot_difficulty}")
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

  command(:set_bot_diff, arguments: 1, help: "!set_bot_diff <bots_per_player>", groups: [:admin, :mod, :director]) do |command|
    diff = command.arguments.first.to_i

    if diff <= 0
      page_player(command.issuer.name, "Invalid bot difficulty, must be greater than 0!")
    elsif diff >= 6
      page_player(command.issuer.name, "Invalid bot difficulty, must be less than 6!")
    else
      @bot_difficulty = diff
      configure_bots

      broadcast_message("[AutoCoop] #{command.issuer.name} has changed the bot difficulty, set to #{@bot_difficulty}")
    end
  end

  command(:set_bot_limit, aliases: [:sbl], arguments: 1, help: "!set_bot_limit <total_bots> - Max bots permitted", groups: [:admin, :mod, :director]) do |command|
    limit = command.arguments.first.to_i

    if limit.zero? || limit.negative?
      page_player(command.issuer.name, "Cannot set bot limit to ZERO or a negative number")
    elsif limit > @hardcap_bot_count
      page_player(command.issuer.name, "Cannot set bot limit to more than #{@hardcap_bot_count}")
    else
      page_player(command.issuer.name, "Bot limit set to #{limit}")
      @max_bot_count = limit
    end
  end

  command(:set_friendless_player_count, aliases: [:sfpc], arguments: 1, help: "!set_friendless_player_count <player_count> - Disables friendly bots after player count is reached", groups: [:admin, :mod, :director]) do |command|
    player_count = command.arguments.first.to_i

    if player_count.negative?
      page_player(command.issuer.name, "Cannot set friendless player count to negative number")
    elsif player_count > @hardcap_friendless_player_count
      page_player(command.issuer.name, "Cannot set friendless player count to more than #{@hardcap_friendless_player_count}")
    else
      page_player(command.issuer.name, "friendless player count set to #{player_count}")
      @friendless_player_count = player_count
    end
  end
end
