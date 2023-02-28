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

    if @versus_started || !@coop_started || player_count.zero?
      bot_count = -1
      RenRem.cmd("botcount 0")

      PluginManager.blackboard_store(:"team_0_bot_count", 0)
      PluginManager.blackboard_store(:"team_1_bot_count", 0)
    elsif player_count >= @friendless_player_count
      # NOTE: Prevent sudden influx of enemy bots when transitioning to exclusive PvE mode
      bot_count = (bot_count / 2.0).round
      RenRem.cmd("botcount #{bot_count} #{(@current_side + 1) % 2}")

      PluginManager.blackboard_store(:"team_#{@current_side}_bot_count", 0)
      PluginManager.blackboard_store(:"team_#{(@current_side + 1) % 2}_bot_count", bot_count)
    else
      RenRem.cmd("botcount #{bot_count}")

      PluginManager.blackboard_store(:"team_#{@current_side}_bot_count", bot_count / 2 - player_count)
      PluginManager.blackboard_store(:"team_#{(@current_side + 1) % 2}_bot_count", bot_count / 2)
    end

    @last_bot_count = bot_count

    return bot_count
  end

  def move_players_to_coop_team
    return unless ServerStatus.total_players.positive?

    PlayerData.player_list.each do |player|
      next unless player.team != @current_side
      next if player.value(:manual_team)

      player.change_team(@current_side)
    end
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

  def revive_naval_buildings
    broadcast_message("[AutoCoop] Reviving Naval Factories...")
    RenRem.cmd("revivebuildingbypreset 0 Sov_Pen")
    RenRem.cmd("revivebuildingbypreset 1 All_Nyd")
  end

  def check_coop_votes(silent:)
    missing = []

    return if ServerStatus.total_players.zero?

    PlayerData.player_list.each do |player|
      next if @coop_votes[player.name] || !player.ingame?

      missing << player
    end

    if missing.size.zero?
      broadcast_message("[AutoCoop] Co-op will be enabled after this round.") unless silent
      log("Co-op will be enabled after this round by player vote") unless silent

      @next_round_mode = :coop

      @coop_votes.clear
      @versus_votes.clear
    else
      broadcast_message("[AutoCoop] Still need #{missing.count} to vote to start coop!") unless silent
    end
  end

  def check_versus_votes(silent:)
    missing = []

    return if ServerStatus.total_players.zero?

    PlayerData.player_list.each do |player|
      next if @versus_votes[player.name] || !player.ingame?

      missing << player
    end

    if missing.size.zero?
      broadcast_message("[AutoCoop] Co-op will be disabled after this round.") unless silent
      log("PvP will be enabled after this round by player vote") unless silent

      @next_round_mode = :versus

      @versus_votes.clear
      @coop_votes.clear
    else
      broadcast_message("[AutoCoop] Still need #{missing.count} to vote for PvP!") unless silent
    end
  end

  def bot_report
    return "0 bots per team" unless @coop_started

    "#{PluginManager.blackboard(:team_0_bot_count).to_i} bots on team #{Teams.name(0)}, #{PluginManager.blackboard(:team_1_bot_count).to_i} bots on team #{Teams.name(1)}"
  end

  on(:start) do
    @current_side = 0
    @bot_difficulty = 3
    @support_bots = 4
    @last_bot_count = -1
    @friendless_player_count = 12
    @max_bot_count = 64
    @hardcap_bot_count = 127 #64
    @hardcap_friendless_player_count = 12
    @base_bot_count = 12
    @max_bot_difficulty = @hardcap_bot_count + 1 # 13 # >= 12

    @default_bot_difficulty = 3
    @default_max_bot_count = 64
    @default_friendless_player_count = 12

    @coop_started = false
    @manual_bot_count = false
    @coop_votes = {}

    @versus_started = false
    @versus_votes = {}
    @advertise_versus_player_count = 8

    @player_characters = {}

    # Attempt to auto resume co-op if bot is restarted
    # NOTE: Probably won't work if a player is a spy
    after(3) do
      team_0 = ServerStatus.get(:team_0_players)
      team_1 = ServerStatus.get(:team_1_players)

      if team_0 > 1 && team_1.zero?
        @coop_started = true
        @versus_started = false
        @current_side = 0

        configure_bots

        broadcast_message("[AutoCoop] Resumed co-op on team #{Teams.name(@current_side)}")
      elsif team_1 > 1 && team_0.zero?
        @coop_started = true
        @versus_started = false
        @current_side = 1

        configure_bots

        broadcast_message("[AutoCoop] Resumed co-op on team #{Teams.name(@current_side)}")
      end
    end

    every(60 * 5) do
      if !@versus_started && @next_round_mode != :versus && ServerStatus.total_players >= @advertise_versus_player_count
        broadcast_message("[AutoCoop] Want some good old Player vs. Player?")
        broadcast_message("[AutoCoop] Vote to switch the next round to PvP with !request_versus (!vs), 100% of players must request it.")
      elsif !@coop_started && @next_round_mode != :coop
        broadcast_message("[AutoCoop] Want to switch back to co-op?")
        broadcast_message("[AutoCoop] Vote to switch the next round to co-op with !request_coop (!rc), 100% of players must request it.")
      end
    end

    # Check that a player is on the correct team and move them if not
    every(5) do
      move_players_to_coop_team if @coop_started
    end
  end

  on(:map_loaded) do |map|
    @current_side += 1
    @current_side %= 2

    @coop_started = false
    @versus_started = false

    @coop_votes.clear
    @versus_votes.clear
    @player_characters.clear

    if @override_current_side
      @current_side = @override_current_side

      log "Restored co-op team to #{Teams.name(@current_side)}, was overridden by map rule."

      @override_current_side = nil
    end

    check_map(map)

    after(5) do
      if ServerStatus.total_players.zero?
        log "Resetting to defaults since no players are in-game."
        @next_round_mode = :coop

        # Reset Co-Op settings to defaults
        @bot_difficulty = @default_bot_difficulty
        @max_bot_count = @default_max_bot_count
        @friendless_player_count = @default_friendless_player_count
      end

      if @next_round_mode == :versus
        @coop_started   = false
        @versus_started = true
      else
        @coop_started   = true
        @versus_started = false
      end

      if @versus_started
        revive_naval_buildings
        configure_bots
      elsif ServerStatus.total_players.positive?
        @coop_started = true

        configure_bots

        log("[AutoCoop] Starting co-op on team #{Teams.name(@current_side)} with #{bot_report}")
        broadcast_message("[AutoCoop] Starting co-op on team #{Teams.name(@current_side)} with #{bot_report}")

        move_players_to_coop_team
      else
        log("No one is in game after 5 seconds, disabling co-op until a player joins.")

        RenRem.cmd("botcount 0")
        @coop_started = false
      end
    end
  end

  on(:player_joined) do |player|
    if @versus_started
      message_player(player.name, "[AutoCoop] Co-op for this round has been disabled. PvP active.")

      configure_bots
    elsif @coop_started || ServerStatus.total_players == 1
      @coop_started = true
      @versus_started = false

      configure_bots

      message_player(player.name, "[AutoCoop] Running co-op on team #{Teams.name(@current_side)} with #{bot_report}")
      player.change_team(@current_side)
    else
      broadcast_message("[AutoCoop] Co-op will automatically begin on the next map.")
      broadcast_message("[AutoCoop] Vote to start now on team #{Teams.name(@current_side)} with !request_coop, 100% of players must request it.")

      configure_bots
    end
  end

  on(:created) do |hash|
    case hash[:type].downcase
    when "soldier"
      @player_characters[hash[:object]] = hash[:preset]
    end
  end

  on(:purchased) do |hash|
    next unless @coop_started

    player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

    next unless player

    case hash[:type].downcase
    when "character"
      if hash[:preset].downcase.include?("_spy_")
        RenRem.cmd("ChangeChar #{player.id} #{@player_characters[hash[:object]]}")
        RenRem.cmd("GiveCredits #{player.id} 500")

        page_player(player.name, "Spies may not be purchased during a co-op match, you have been refunded and returned to your previous character.")
      end
    end
  end

  on(:player_left) do |player|
    @coop_votes.delete(player.name)
    @versus_votes.delete(player.name)

    # Player is still logically connected until after this
    # callback has been issued by the PluginManager.
    after(1) do
      configure_bots
    end
  end

  command(:coop_info, aliases: [:ci], arguments: 0, help: "Reports co-op configuration") do |command|
    page_player(
      command.issuer.name,
      "[AutoCoop] PvP: #{@versus_started}, PvE: #{@coop_started}, "\
      "Bots: #{@last_bot_count}/#{@max_bot_count} (hard cap: #{@hardcap_bot_count}), "\
      "Bot Diff: #{@bot_difficulty}/#{@max_bot_difficulty}, "\
      "Friendless Player Count: #{@friendless_player_count} (hard cap: #{@hardcap_friendless_player_count})")
  end

  command(:botcount, aliases: [:bc], arguments: 0, help: "Reports number of bots configured") do |command|
    broadcast_message("[AutoCoop] There are #{bot_report}")
  end

  command(:bot_diff, aliases: [:bd], arguments: 0, help: "Reports bot difficulty (bots per player)") do |command|
    broadcast_message("[AutoCoop] Bot difficulty is set to #{@bot_difficulty}")
  end

  command(:bot_limit, aliases: [:botl], arguments: 0, help: "Reports bot limit") do |command|
    broadcast_message("[AutoCoop] Bot limit is set to #{@max_bot_count}")
  end

  command(:friendless_player_count, aliases: [:fpc], arguments: 0, help: "Reports friendless player count") do |command|
    broadcast_message("[AutoCoop] Friendless Player Count is set to #{@friendless_player_count}")
  end

  command(:request_coop, aliases: [:rc], arguments: 0, help: "Vote to start coop") do |command|
    if @next_round_mode == :coop
      page_player(command.issuer.name, "Co-op is already set to start on the next round!")
    else
      @coop_votes[command.issuer.name] = true
      check_coop_votes(silent: false)
    end
  end

  command(:request_versus, aliases: [:vs], arguments: 0, help: "Vote to start Player vs. Player") do |command|
    if @next_round_mode == :versus
      page_player(command.issuer.name, "PvP is already set to start on the next round!")
    else
      @versus_votes[command.issuer.name] = true
      check_versus_votes(silent: false)
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
      @next_round_mode = :coop

      @current_side = team
      @coop_started = true
      @versus_started = false

      configure_bots
      move_players_to_coop_team

      broadcast_message("[AutoCoop] #{command.issuer.name} has started co-op on team #{Teams.name(@current_side)} with #{bot_report}")
    else
      page_player(command.issuer.name, "[AutoCoop] Failed to detect team for: #{command.arguments.first}, got #{team}, try again.")
    end
  end

  command(:versus, arguments: 1, help: "!versus NOW - Switch to Player vs. Player for this round.", groups: [:admin, :mod, :director]) do |command|
    if command.arguments.first == "NOW"
      @next_round_mode = :versus

      @coop_started = false
      @versus_started = true

      configure_bots
      remix_teams

      broadcast_message("#{command.issuer.name} has started Player vs. Player.")
    else
      page_player(command.issuer.name, "Use !versus NOW if you really mean it.")
    end
  end

  command(:set_bot_diff, aliases: [:sbd], arguments: 1, help: "!set_bot_diff <bots_per_player>", groups: [:admin, :mod, :director]) do |command|
    diff = command.arguments.first.to_i

    if diff <= 0
      page_player(command.issuer.name, "Invalid bot difficulty, must be greater than 0!")
    elsif diff >= @max_bot_difficulty
      page_player(command.issuer.name, "Invalid bot difficulty, must be less than #{@max_bot_difficulty}!")
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

      configure_bots
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

      configure_bots
    end
  end
end
