mobius_plugin(name: "AutoCoop", database_name: "auto_coop", version: "0.0.1") do
  def configure_bots
    player_count = ServerStatus.total_players
    bot_count = player_count * @bot_difficulty
    bot_count = @min_bot_count if bot_count.zero? || bot_count < @min_bot_count

    bot_count = @max_bot_count if bot_count > @max_bot_count

    # Cannot use botcount with asymmetric bot count 😭
    # if @current_side == 0
    #   RenRem.cmd("botcount #{player_count + @support_bots} 0")
    #   RenRem.cmd("botcount #{bot_count} 1")
    # else
    #   RenRem.cmd("botcount #{player_count + @support_bots} 1")
    #   RenRem.cmd("botcount #{bot_count} 0")
    # end

    if player_count.zero? # Idle server
      RenRem.cmd("botcount 0")

      PluginManager.blackboard_store(:"team_0_bot_count", 0)
      PluginManager.blackboard_store(:"team_1_bot_count", 0)
    elsif @versus_started || !@coop_started
      if !@versus_configured && @versus_persistent_bot_padding == 0
        @versus_configured = true
        bot_count = MapSettings.get_map_setting(:botcount) || 0

        RenRem.cmd("botcount #{bot_count}")

        PluginManager.blackboard_store(:"team_0_bot_count", bot_count > 0 ? (bot_count / 2.0).ceil : 0)
        PluginManager.blackboard_store(:"team_1_bot_count", bot_count > 0 ? (bot_count / 2.0).ceil : 0)
      elsif @versus_persistent_bot_padding > 0
        bot_count = player_count + (@versus_persistent_bot_padding.clamp(0, @max_bot_count) * 2)

        RenRem.cmd("botcount #{bot_count}")

        PluginManager.blackboard_store(:"team_0_bot_count", bot_count > 0 ? (bot_count / 2.0).ceil : 0)
        PluginManager.blackboard_store(:"team_1_bot_count", bot_count > 0 ? (bot_count / 2.0).ceil : 0)
      end
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

  def autobalance_notifier
    team_zero_count = PlayerData.players_by_team(0).size
    team_one_count = PlayerData.players_by_team(1).size

    team_zero_count -= @known_spies.size
    team_one_count += @known_spies.size

    team_diff = team_zero_count - team_one_count
    even_teams = (team_diff >= 2 || team_diff <= -2)
    even_team_zero = even_teams && team_diff.positive?

    if even_teams
      team_id = even_team_zero ? 0 : 1
      RenRem.cmd("evat #{team_id} interface_escape.wav")
      message_team(team_id, "[MOBIUS] Please even the teams. Use !rtc or !swap to change teams.", red: 64, green: 255, blue: 64)
    end

    @last_autobalance_notified = monotonic_time
  end

  def check_map(map)
    name = map.split(".", 2).first

    if (config[:force_team_0_maps] || []).include?(name)
      @current_side = 0
    elsif (config[:force_team_1_maps] || []).include?(name)
      @current_side = 1
    end
  end

  def revive_naval_buildings
    # broadcast_message("[AutoCoop] Reviving Naval Factories...")
    RenRem.cmd("revivebuildingbypreset 0 Sov_Pen")
    RenRem.cmd("revivebuildingbypreset 1 All_Nyd")
  end

  def bot_report
    return "#{(@last_bot_count / 2.0).round} bots per team" unless @coop_started

    "#{PluginManager.blackboard(:team_0_bot_count).to_i} bots on team #{Teams.name(0)}, #{PluginManager.blackboard(:team_1_bot_count).to_i} bots on team #{Teams.name(1)}"
  end

  on(:start) do
    @start_time = monotonic_time

    # Loaded from config
    @default_mode = (config[:default_mode] || "coop").to_sym
    @default_bot_difficulty = config[:default_bot_difficulty] || 3
    @default_max_bot_count = config[:default_max_bot_count] || 64
    @default_friendless_player_count = config[:default_friendless_player_count] || 12
    @min_bot_count = config[:min_bot_count] || 12
    @hardcap_bot_count = config[:hardcap_bot_count] || 127 #64
    @hardcap_friendless_player_count = config[:hardcap_friendless_player_count] || 12

    @advertise_mode_player_count = config[:advertise_mode_player_count] || 8

    @next_round_mode = @default_mode
    @current_side = 0
    @bot_difficulty = @default_bot_difficulty
    @friendless_player_count = @default_friendless_player_count
    @max_bot_count = @default_max_bot_count
    @max_bot_difficulty = @hardcap_bot_count + 1 # 13 # >= 12
    @last_bot_count = -1
    @support_bots = 4 # Not a thing... :sad:

    @coop_started = false
    @manual_bot_count = false

    @versus_started = false
    @versus_configured = false
    @versus_persistent_bot_padding = config[:versus_persistent_bot_padding] || 0

    @allow_spy_purchases_in_coop = config[:allow_spy_purchases_in_coop] || false
    @spy_presets = (config[:spy_presets] || [
      "Allied_Spy_Rifle",
      "Allied_Spy_Flame",
      "Allied_Spy_Shock",
      "Allied_Spy_Tech"
    ]).map(&:downcase).map(&:strip)

    PluginManager.blackboard_store(:allow_spy_purchases_in_coop, @allow_spy_purchases_in_coop)
    PluginManager.blackboard_store(:auto_coop_spy_presets, @spy_presets)

    @player_characters = {}
    @last_autobalance_notified = 0
    @autobalance_notifier_interval = 30.0 # seconds
    @known_spies = {}

    # Attempt to auto resume co-op if bot is restarted
    # NOTE: Probably won't work if a player is a spy
    after(3) do
      team_0 = ServerStatus.get(:team_0_players)
      team_1 = ServerStatus.get(:team_1_players)

      if @default_mode == :versus
        @versus_started = true
        @versus_configured = false

        configure_bots
      elsif team_0 > 1 && team_1.zero?
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

    # Check that a player is on the correct team and move them if not
    every(5) do
      move_players_to_coop_team if @coop_started

      autobalance_notifier if @versus_started && monotonic_time - @last_autobalance_notified >= @autobalance_notifier_interval
    end
  end

  on(:map_loaded) do |map|
    @current_side += 1
    @current_side %= 2

    @coop_started = false
    @versus_started = false

    @player_characters.clear
    @known_spies.clear

    check_map(map)

    after(5) do
      if ServerStatus.total_players.zero?
        log "Resetting to defaults since no players are in-game."
        @next_round_mode = @default_mode

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
        @versus_configured = false

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

    after(15) do
      if !@versus_started && @next_round_mode != :versus && ServerStatus.total_players >= @advertise_mode_player_count
        broadcast_message("[AutoCoop] Want some good old Player vs. Player?")
        broadcast_message("[AutoCoop] Vote to switch the next round to PvP with !vote versus (!v versus), 69% of players must request it.")
      elsif !@coop_started && @next_round_mode != :coop && ServerStatus.total_players >= @advertise_mode_player_count
        broadcast_message("[AutoCoop] Want to switch back to co-op?")
        broadcast_message("[AutoCoop] Vote to switch the next round to co-op with !vote coop (!v coop), 69% of players must request it.")
      end
    end
  end

  on(:player_joined) do |player|
    baby_bot = monotonic_time - @start_time <= 1.0

    if @versus_started
      message_player(player, "[AutoCoop] Co-op for this round has been disabled. PvP active.") unless @default_mode == :versus

      configure_bots
    elsif @coop_started || ServerStatus.total_players == 1
      @coop_started = true
      @versus_started = false

      configure_bots

      message_player(player, "[AutoCoop] Running co-op on team #{Teams.name(@current_side)} with #{bot_report}")
      player.change_team(@current_side)
    elsif !baby_bot
      broadcast_message("[AutoCoop] Co-op will automatically begin on the next map.") if @next_round_mode == :coop

      configure_bots
    end
  end

  on(:created) do |hash|
    case hash[:type].downcase
    when "soldier"
      @player_characters[hash[:object]] = hash[:preset]

      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

      if player
        if !@allow_spy_purchases_in_coop && @spy_presets.include?(hash[:preset].downcase)
          @known_spies[player.name] = true
        elsif @known_spies.delete(player.name)
        end
      end
    end
  end

  on(:purchased) do |hash|
    next unless @coop_started

    player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

    next unless player

    case hash[:type].downcase
    when "character"
      if !@allow_spy_purchases_in_coop && @spy_presets.include?(hash[:preset].downcase)
        RenRem.cmd("ChangeChar #{player.id} #{@player_characters[hash[:object]]}")
        RenRem.cmd("GiveCredits #{player.id} 500")

        page_player(player, "Spies may not be purchased during a co-op match, you have been refunded and returned to your previous character.")
      end
    end
  end

  on(:player_left) do |player|
    # Player is still logically connected until after this
    # callback has been issued by the PluginManager.
    after(1) do
      configure_bots
    end
  end

  command(:coop_info, aliases: [:ci], arguments: 0, help: "Reports co-op configuration") do |command|
    page_player(
      command.issuer,
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
      page_player(command.issuer, "[AutoCoop] Failed to detect team for: #{command.arguments.first}, got #{team}, try again.")
    end
  end

  command(:versus, arguments: 1, help: "!versus NOW/NEXT - Switch to Player vs. Player for this or next round.", groups: [:admin, :mod, :director]) do |command|
    if command.arguments.first == "NOW"
      @next_round_mode = :versus

      @coop_started = false
      @versus_started = true
      @versus_configured = false

      configure_bots
      remix_teams

      broadcast_message("#{command.issuer.name} has started Player vs. Player.")
    elsif command.arguments.first == "NEXT"
      @next_round_mode = :versus

      page_player(command.issuer, "The next round will be versus.")
    else
      page_player(command.issuer, "Use !versus NOW/NEXT if you really mean it.")
    end
  end

  command(:versus_bot_padding, aliases: [:vbp], arguments: 0, help: "!vbp - Number of bots on each team along side players, 0 is disabled and uses map settings configured bot count.", groups: [:admin, :mod, :director]) do |command|
    page_player(command.issuer, "Versus bot padding is #{@versus_persistent_bot_padding}.")
  end

  command(:set_versus_bot_padding, aliases: [:svbp], arguments: 1, help: "!svbp <number> - Set number of bots to have on each team along side players, 0 to disable and use map settings configured bot count.", groups: [:admin, :mod, :director]) do |command|
    bot_padding = command.arguments.first.to_i

    @versus_persistent_bot_padding = bot_padding
    configure_bots

    page_player(command.issuer, "Versus bot padding has been set to #{bot_padding}.")
  end

  command(:set_bot_diff, aliases: [:sbd], arguments: 1, help: "!set_bot_diff <bots_per_player>", groups: [:admin, :mod, :director]) do |command|
    diff = command.arguments.first.to_i

    if diff <= 0
      page_player(command.issuer, "Invalid bot difficulty, must be greater than 0!")
    elsif diff >= @max_bot_difficulty
      page_player(command.issuer, "Invalid bot difficulty, must be less than #{@max_bot_difficulty}!")
    else
      @bot_difficulty = diff
      configure_bots

      broadcast_message("[AutoCoop] #{command.issuer.name} has changed the bot difficulty, set to #{@bot_difficulty}")
    end
  end

  command(:set_bot_limit, aliases: [:sbl], arguments: 1, help: "!set_bot_limit <total_bots> - Max bots permitted", groups: [:admin, :mod, :director]) do |command|
    limit = command.arguments.first.to_i

    if limit.zero? || limit.negative?
      page_player(command.issuer, "Cannot set bot limit to ZERO or a negative number")
    elsif limit > @hardcap_bot_count
      page_player(command.issuer, "Cannot set bot limit to more than #{@hardcap_bot_count}")
    else
      page_player(command.issuer, "Bot limit set to #{limit}")
      @max_bot_count = limit

      configure_bots
    end
  end

  command(:set_friendless_player_count, aliases: [:sfpc], arguments: 1, help: "!set_friendless_player_count <player_count> - Disables friendly bots after player count is reached", groups: [:admin, :mod, :director]) do |command|
    player_count = command.arguments.first.to_i

    if player_count.negative?
      page_player(command.issuer, "Cannot set friendless player count to negative number")
    elsif player_count > @hardcap_friendless_player_count
      page_player(command.issuer, "Cannot set friendless player count to more than #{@hardcap_friendless_player_count}")
    else
      page_player(command.issuer, "friendless player count set to #{player_count}")
      @friendless_player_count = player_count

      configure_bots
    end
  end

  vote(:coop, arguments: 0, description: "Vote to switch next match to co-op") do |vote|
    if vote.validate?
      b = @next_round_mode != :coop
      page_player(vote.issuer, "Cannot vote to start co-op on next match, already set.") unless b
      b
    elsif vote.commit?
      @next_round_mode = :coop
    end
  end

  vote(:versus, arguments: 0, description: "Vote to switch next match to versus") do |vote|
    if vote.validate?
      b = @next_round_mode != :versus
      page_player(vote.issuer, "Cannot vote to start versus on next match, already set.") unless b
      b
    elsif vote.commit?
      @next_round_mode = :versus
    end
  end
end
