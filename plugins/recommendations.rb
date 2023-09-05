mobius_plugin(name: "Recommendations", database_name: "recommendations", version: "0.0.1") do
  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    # DEBUG Logging
    @debugging = false

    @allow_auto_recs = false

    @teamplayers_timeout = 120 # seconds - how often the !tp/!n00bs command my be used
    @team_players_last_used = -@teamplayers_timeout

    @autorec_cache = {}
  end

  on(:player_joined) do |player|
    @allow_auto_recs ||= allow_auto_recs?

    show_joinmessage(player)
  end

  on(:map_loaded) do |map|
    @allow_auto_recs = allow_auto_recs?

    @autorec_cache = {}
  end

  on(:killed) do |object, raw|
    next unless @allow_auto_recs

    player = PlayerData.player(PlayerData.name_to_id(object[:killer_name]))
    next unless player
    next unless player.team == 0 || player.team == 1
    next unless object[:_killed_object] && object[:_killed_object][:team] != player.team && object[:_killed_object][:team].between?(0, 1)

    @autorec_cache[player.name] ||= {}

    case object[:killed_type].to_s.downcase.to_sym
    when :building
      gamelog_building_killed(player, object)
    when :vehicle
      gamelog_vehicle_killed(player, object)
    when :soldier
      gamelog_soldier_killed(player, object)
    end
  end

  on(:damaged) do |object, raw|
    next unless @allow_auto_recs

    player = object[:_damager_player_object]

    next unless player
    next unless player.team == 0 || player.team == 1
    next unless object[:_damaged_object] && object[:_damaged_object][:team] != player.team && object[:_damaged_object][:team].between?(0, 1)

    @autorec_cache[player.name] ||= {}

    case object[:type].to_s.downcase.to_sym
    when :building
      gamelog_building_damaged(player, object)
    when :vehicle
      gamelog_vehicle_damaged(player, object)
    when :soldier
      gamelog_soldier_damaged(player, object)
    end
  end

  command(:recommend, aliases: [:rec], arguments: 2, help: "!rec <nickname> <comment> - Recommend another player for good teamplay, etc.") do |command|
    recommend(:rec, command)
  end

  command(:n00b, aliases: [:noob], arguments: 2, help: "!n00b <nickname> <comment> - Mark another player as a n00b.") do |command|
    recommend(:n00b, command)
  end

  command(:recommendations, aliases: [:recs], help: "!recs - Shows your current recommendations.") do |command|
    recommendations(command.issuer)
  end

  command(:teamplayers, aliases: [:tp], help: "!tp - Displays all teamplayers.") do |command|
    team_players(:rec)
  end

  command(:shown00bs, aliases: [:shownoobs, :n00bs, :noobs], help: "!n00bs - Displays all n00bs.") do |command|
    team_players(:n00b)
  end

  command(:recignore, arguments: 1, help: "!recignore <nickname> - Disables recommendations for a specific user.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      Database::Log.create(
        log_code: Mobius::LOG_CODE[:reclog],
        log: "[RECOMMENDATION] #{player.name} was rec ignored by #{command.issuer.name}."
      )

      database_set(command.issuer.name.downcase, "false")
      page_player(command.issuer.name, "[MOBIUS] #{player.name} is now recignored.")
    else
      page_player(command.issuer.name, "[MOBIUS] #{command.arguments.first} is not ingame, or the name is not unique.")
    end
  end

  command(:recallow, arguments: 1, help: "!recallow <nickname> - Enables recommendations for a specific user.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      Database::Log.create(
        log_code: Mobius::LOG_CODE[:reclog],
        log: "[RECOMMENDATION] #{player.name} was rec allowed by #{command.issuer.name}."
      )

      database_remove(command.issuer.name.downcase)
      page_player(command.issuer.name, "[MOBIUS] #{player.name} is now recallowed.")
    else
      page_player(command.issuer.name, "[MOBIUS] #{command.arguments.first} is not ingame, or the name is not unique.")
    end
  end

  def recommend(mode, command)
    noob = mode == :n00b
    recommender = command.issuer
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    comment = command.arguments.last

    if player
      if recommender.name == player.name
        page_player(recommender.name, "[MOBIUS] You cannot #{noob ? 'n00b' : 'recommend'} youself.")
        return
      end

      if rec_ignored?(player)
        page_player(recommender.name, "[MOBIUS] Sorry, the server administrators have disabled recommendations for you.")
        return
      end

      recommend_status = recommend_status(recommender, player, noob)
      case recommend_status
      when :allowed
        recommend_player(recommender.name.downcase, player, comment, noob)
      when :limit_reached
        page_player(recommender.name, "[MOBIUS] You have reached your daily limit for n00bs.") if noob
        page_player(recommender.name, "[MOBIUS] You have reached your daily limit for recommendations.") unless noob
      when :already_recommended_today
        page_player(recommender.name, "[MOBIUS] You have already recommended #{player.name} today.")
      when :already_noobed_today
        page_player(recommender.name, "[MOBIUS] You have already n00bed #{player.name} today.")
      end
    else
      page_player(recommender.name, "[MOBIUS] Player #{command.arguments.first} was not found ingame, or is not unique.")
    end
  end

  def recommendations(player)
    recommendations = Database::RecommendationCounterCache.first(Sequel.ilike(:player_name, player.name)) # ILIKE, case insensitive

    count = recommendations ? recommendations.recommendations - recommendations.noobs : 0
    page_player(player.name, "[MOBIUS] You currently have #{count} recommendations. ( #{recommendations.recommendations} recs, #{recommendations.noobs} n00bs )")
  end

  def team_players(mode)
    noob = mode == :n00b

    if monotonic_time - @team_players_last_used < @teamplayers_timeout
      broadcast_message("[MOBIUS] The !teamplayers/!shown00bs command can only be used once every 2 minutes! Use !recs to see your own recommendations.")
      return
    else
      @team_players_last_used = monotonic_time
    end

    team_0_recs = 0
    team_1_recs = 0
    team_0_noobs = 0
    team_1_noobs = 0
    team_0 = []
    team_1 = []
    PlayerData.player_list.select(&:ingame?).each do |player|
      recommendations = Database::RecommendationCounterCache.first(Sequel.ilike(:player_name, player.name)) # ILIKE, case insensitive

      if recommendations
        if player.team == 0
          team_0_recs += recommendations.recommendations
          team_0_noobs += recommendations.noobs
          team_0 << "#{player.name} #{recommendations.noobs - recommendations.recommendations}" if noob && (recommendations.noobs - recommendations.recommendations) > 0
          team_0 << "#{player.name} #{recommendations.recommendations - recommendations.noobs}" if !noob && (recommendations.recommendations - recommendations.noobs) > 0
        end

        if player.team == 1
          team_1_recs += recommendations.recommendations
          team_1_noobs += recommendations.noobs
          team_1 << "#{player.name} #{recommendations.noobs - recommendations.recommendations}" if noob && (recommendations.noobs - recommendations.recommendations) > 0
          team_1 << "#{player.name} #{recommendations.recommendations - recommendations.noobs}" if !noob && (recommendations.recommendations - recommendations.noobs) > 0
        end
      end
    end

    if noob
      if team_0_noobs + team_1_noobs == 0
        broadcast_message("[MOBIUS] None of the players in the server have any n00bs.")
      else
        broadcast_message("[MOBIUS] n00bs based on in-game complaints")

        if team_0.size > 0
          broadcast_message("[MOBIUS] #{Teams.name(0)}")
          team_0.each do |str|
            broadcast_message("[MOBIUS]     #{str}")
          end
        end

        if team_1.size > 0
          broadcast_message("[MOBIUS] #{Teams.name(1)}")
          team_1.each do |str|
            broadcast_message("[MOBIUS]     #{str}")
          end
        end
      end
    else # recs
      if team_0_recs + team_1_recs == 0
        broadcast_message("[MOBIUS] None of the players in the server have any recommendations.")
      else
        broadcast_message("[MOBIUS] Team players based on in-game recommendations")

        if team_0.size > 0
          broadcast_message("[MOBIUS] #{Teams.name(0)}")
          team_0.each do |str|
            broadcast_message("[MOBIUS]     #{str}")
          end
        end

        if team_1.size > 0
          broadcast_message("[MOBIUS] #{Teams.name(1)}")
          team_1.each do |str|
            broadcast_message("[MOBIUS]     #{str}")
          end
        end
      end
    end
  end

  def recommend_status(recommender, player, noob)
    cutoff = Time.at(Time.now.utc.to_i - (1440 * 60)) # 1 day

    results = Database::Recommendation.select.where(Sequel.ilike(:recommender_name, recommender.name)).where(noob: noob).where { created_at >= cutoff }.all

    already_operated = results.select do |r|
      r.recommender_name.downcase == recommender.name.downcase &&
      r.player_name.downcase == player.name.downcase
    end

    if already_operated.size.positive?
      pp already_operated

      return :already_noobed_today if already_operated.last.noob && noob
      return :already_recommended_today unless already_operated.last.noob && noob
    end

    return :limit_reached if results.count >= 5

    return :allowed
  end

  def allow_auto_recs?
    config[:enable_for_coop] || (PlayerData.players_by_team(0).size > 0 && PlayerData.players_by_team(1).size > 0)
  end

  def rec_ignored?(player)
    database_get(player.name.downcase)
  end

  def recommend_player(recommender_name, player, comment, noob, autorec = false)
    return if rec_ignored?(player)

    player_name = player.name

    if noob
      broadcast_message("[MOBIUS] #{player.name} has been been marked a n00b by #{recommender_name} for: #{comment}")
    else
      broadcast_message("[MOBIUS] #{player.name} has been recommended by #{recommender_name} for: #{comment}")
    end

    # Only play sound if player is recommended
    unless noob
      if player.team == 0
        RenRem.cmd("snda #{config[:team_0_sound] || 'rokroll1.wav'}")
      else
        RenRem.cmd("snda #{config[:team_1_sound] || 'jyes1.wav'}")
      end
    end

    recommendation = Database::Recommendation.create(recommender_name: recommender_name, player_name: player_name, comment: comment, noob: noob, autorec: autorec)
    counter_cache = Database::RecommendationCounterCache.first(Sequel.ilike(:player_name, player_name)) # ILIKE, case insensitive

    if recommendation.save
      if counter_cache
        noob ? counter_cache.update(noobs: counter_cache.noobs + 1) : counter_cache.update(recommendations: counter_cache.recommendations + 1)
      else
        counter_cache = Database::RecommendationCounterCache.create(player_name: player_name, noobs: (noob ? 1 : 0), recommendations: (!noob ? 1 : 0))
      end

      counter_cache.save
    else
      # FAILED TO SAVE...
    end
  end

  def show_joinmessage(player)
    recommendations = Database::RecommendationCounterCache.first(Sequel.ilike(:player_name, player.name)) # ILIKE, case insensitive

    count = recommendations ? recommendations.recommendations - recommendations.noobs : 0
    if count.zero? || count.negative?
      broadcast_message("[MOBIUS] #{player.name} does not have any recommendations yet.")
    else
      broadcast_message("[MOBIUS] #{player.name} has #{count} recommendations.")
    end
  end

  ###--------------------------- Auto Recommendation Handlers ---------------------------###
  #############
  ### KILLS ###
  #############
  def gamelog_building_killed(player, object)
    return if config[:autorec][:building_kills].to_i <= 0

    @autorec_cache[player.name][:building_kills] ||= 0
    @autorec_cache[player.name][:building_kills] += 1

    @autorec_cache[player.name][:buildings_killed] ||= []
    @autorec_cache[player.name][:buildings_killed] << Presets.translate(object[:killed_preset])

    buildings = @autorec_cache[player.name][:buildings_killed]

    log "[#{player.name}] Building kills: #{buildings.size}" if @debugging

    # Do autorec
    if buildings.size >= config[:autorec][:building_kills]
      autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

      message = if buildings.size > 2
        "Destroying #{buildings[0..(buildings.size - 2)].join(', ')} and #{buildings.last}"
      elsif buildings.size > 1
        "Destroying #{buildings.first} and #{buildings.last}"
      else
        "Destroying #{buildings.first}"
      end

      recommend_player(autorec_name, player, message, false, true)

      @autorec_cache[player.name][:building_kills] = 0
      @autorec_cache[player.name][:buildings_killed].clear
    end
  end

  def gamelog_vehicle_killed(player, object)
    return if config[:autorec][:vehicle_kills].to_i <= 0

    @autorec_cache[player.name][:vehicle_kills] ||= 0
    @autorec_cache[player.name][:vehicle_kills] += 1

    vehicles = @autorec_cache[player.name][:vehicle_kills]

    log "[#{player.name}] Vehicle kills: #{vehicles}" if @debugging

    # Do autorec
    if vehicles >= config[:autorec][:vehicle_kills]
      autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

      recommend_player(autorec_name, player, "Destroying #{vehicles} enemy vehicles", false, true)

      @autorec_cache[player.name][:vehicle_kills] = 0
    end
  end

  def gamelog_soldier_killed(player, object)
    return if config[:autorec][:infantry_kills].to_i <= 0

    @autorec_cache[player.name][:vehicle_kills] ||= 0
    @autorec_cache[player.name][:vehicle_kills] += 1

    kills = @autorec_cache[player.name][:vehicle_kills]

    log "[#{player.name}] Infantry kills: #{kills}" if @debugging

    # Do autorec
    if kills >= config[:autorec][:infantry_kills]
      autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

      recommend_player(autorec_name, player, "Killing #{kills} enemy infantry", false, true)

      @autorec_cache[player.name][:vehicle_kills] = 0
    end
  end

  ##################################
  ### REPAIRS/HEALING and DAMAGE ###
  ##################################
  def gamelog_building_damaged(player, object)
    # Healiong recs
    if config[:autorec][:building_repair].to_i > 0
      @autorec_cache[player.name][:building_repairs] ||= 0
      @autorec_cache[player.name][:building_repairs] -= object[:damage] if object[:damage].negative?

      repairs = @autorec_cache[player.name][:building_repairs]

      log "[#{player.name}] Building repairs: #{repairs}" if @debugging

      if repairs >= config[:autorec][:building_repair]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Engineering Support", false, true)

        @autorec_cache[player.name][:building_repair] = 0
      end
    end

    # Damage recs
    if config[:autorec][:building_damage].to_i > 0
      @autorec_cache[player.name][:building_damage] ||= 0
      @autorec_cache[player.name][:building_damage] += object[:damage] unless object[:damage].negative?

      damage = @autorec_cache[player.name][:building_damage]

      log "[#{player.name}] Building damage: #{damage}" if @debugging

      if damage >= config[:autorec][:building_damage]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Damaging enemy structures", false, true)

        @autorec_cache[player.name][:building_damage] = 0
      end
    end
  end

  def gamelog_vehicle_damaged(player, object)
    # Healiong recs
    if config[:autorec][:vehicle_repair].to_i > 0
      @autorec_cache[player.name][:vehicle_repair] ||= 0
      @autorec_cache[player.name][:vehicle_repair] -= object[:damage] if object[:damage].negative?

      repairs = @autorec_cache[player.name][:vehicle_repair]

      log "[#{player.name}] Vehicle repairs: #{repairs}" if @debugging

      if repairs >= config[:autorec][:vehicle_repair]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Mechanical Support", false, true)

        @autorec_cache[player.name][:vehicle_repair] = 0
      end
    end

    # Damage recs
    if config[:autorec][:vehicle_damage].to_i > 0
      @autorec_cache[player.name][:vehicle_damage] ||= 0
      @autorec_cache[player.name][:vehicle_damage] += object[:damage] unless object[:damage].negative?

      damage = @autorec_cache[player.name][:vehicle_damage]

      log "[#{player.name}] Vehicle damage: #{damage}" if @debugging

      if damage >= config[:autorec][:vehicle_damage]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Damaging enemy vehicles", false, true)

        @autorec_cache[player.name][:vehicle_damage] = 0
      end
    end
  end

  def gamelog_soldier_damaged(player, object)
    # Healiong recs
    if config[:autorec][:infantry_healing].to_i > 0

      @autorec_cache[player.name][:infantry_healing] ||= 0
      @autorec_cache[player.name][:infantry_healing] -= object[:damage] if object[:damage].negative?

      healing = @autorec_cache[player.name][:infantry_healing]

      log "[#{player.name}] Infantry healing: #{healing}" if @debugging

      if healing >= config[:autorec][:infantry_healing]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Medical Support", false, true)

        @autorec_cache[player.name][:infantry_healing] = 0
      end
    end

    # Damage recs
    if config[:autorec][:infantry_damage].to_i > 0
      @autorec_cache[player.name][:infantry_damage] ||= 0
      @autorec_cache[player.name][:infantry_damage] += object[:damage] unless object[:damage].negative?

      damage = @autorec_cache[player.name][:infantry_damage]

      log "[#{player.name}] Infantry damage: #{damage}" if @debugging

      if damage >= config[:autorec][:infantry_damage]
        autorec_name = config[:autorec][:commanders][:"team_#{player.team}"].sample

        recommend_player(autorec_name, player, "Damaging enemy infantry", false, true)

        @autorec_cache[player.name][:infantry_damage] = 0
      end
    end
  end
end
