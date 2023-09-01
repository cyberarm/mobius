mobius_plugin(name: "Recommendations", database_name: "recommendations", version: "0.0.1") do
  on(:start) do
    @allow_recs = false # FIXME

    @autorec_cache = {}
  end

  on(:player_join) do |player|
    @allow_recs = false # FIXME

    show_joinmessage(player)
  end

  on(:player_left) do |player|
    @allow_recs = false # FIXME
  end

  on(:map_loaded) do |map|
    @allow_recs = false # FIXME
  end

  # TODO
  on(:killed) do |object, raw|
  end

  # TODO
  on(:damaged) do |object, raw|
  end

  command(:recommend, aliases: [:rec], arguments: 2, help: "Recommend another player for good teamplay, etc.") do |command|
    recommend(:rec, command)
  end

  command(:n00b, aliases: [:noob], arguments: 2, help: "Recommend another player for good teamplay, etc.") do |command|
    recommend(:n00b, command)
  end

  command(:recommendations, aliases: [:recs], help: "Shows your current recommendations.") do |command|
    recommendations(command.issuer)
  end

  command(:teamplayers, aliases: [:tp], help: "Displays all teamplayers.") do |command|
  end

  command(:shown00bs, aliases: [:shownoobs, :n00bs, :noobs], help: "Displays all n00bs.") do |command|
  end

  command(:recignore, arguments: 1, help: "Disables recommendations for a specific user.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first))

    if player
      Database::Log.create(
        log_code: Mobius::LOG_CODE[:reclog],
        log: "[RECOMMENDATION] #{player.name} was rec ignored by #{command.issuer.name}."
      )

      database_set(command.issuer.name.downcase, "false")
    else
      page_player(command.issuer.name, "[MOBIUS] #{command.arguments.first} is not ingame, or the name is not unique.")
    end
  end

  command(:recallow, arguments: 1, help: "Enables recommendations for a specific user.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first))

    if player
      Database::Log.create(
        log_code: Mobius::LOG_CODE[:reclog],
        log: "[RECOMMENDATION] #{player.name} was rec allowed by #{command.issuer.name}."
      )

      database_remove(command.issuer.name.downcase)
    else
      page_player(command.issuer.name, "[MOBIUS] #{command.arguments.first} is not ingame, or the name is not unique.")
    end
  end

  def recommend(mode, command)
    noob = mode == :n00b
    recommender = command.issuer
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first))
    comment = command.arguments.last

    if player
      if recommender.name == player.name && !noob
        page_player(recommender.name, "[MOBIUS] You are not allowed to recommend youself.")
        return
      end

      if rec_ignored?(player)
        page_player(recommender.name, "[MOBIUS] Sorry, the server administrators have disabled recommendations for you.")
        return
      end

      if player.name == recommender.name
        page_player(recommender.name, "[MOBIUS] You cannot recommend yourself.")
        return
      end

      recommend_status = recommend_status(recommender, player, noob)
      case recommend_status
      when :allowed
        recommend_player(recommender.name.downcase, player.name.downcase, comment, noob)
      when :limit_reached
        page_player(recommender.name, "[MOBIUS] You have reached your daily limit for recommendations.")
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
    recommendations = Database::RecommendationCounterCache.first(name: player.name.downcase)

    count = recommendations ? recommendations.recommendations - recommendations.noobs : 0
    page_player(player.name, "[MOBIUS] You currently have #{count} recommendations. ( #{recommendations.recommendations} recs, #{recommendations.noobs} n00bs )")
  end

  def can_recommend?(recommender, player, noob)


    false
  end

  def rec_ignored?(player)
    database_get(player.name.downcase)
  end

  def recommend_player(recommender_name, player, comment, noob)
    player_name = player.name

    broadcast_message("[MOBIUS] #{player.name} has been recommended by #{recommender_name} for: #{comment}")

    if player.team == 0
      RenRem.cmd("snda rokroll1.wav")
    else
      RenRem.cmd("snda jyes1.wav")
    end

    recommendation = Database::Recommendation.create(recommender_name: recommender_name, player_name: player_name, comment: comment, noob: noob)
    counter_cache = Database::RecommendationCounterCache.first(player_name: player_name)

    if recommendation.save
      if counter_cache
        noob ? counter_cache.update(noobs: counter_cache.noob + 1) : counter_cache.update(recommendations: counter_cache.recommendations + 1)
      else
        counter_cache = Database::RecommendationCounterCache.create(player_name: player_name)
        counter_cache.save
      end
    else
      # FAILED TO SAVE...
    end
  end

  def show_joinmessage(player)
    recommendations = Database::RecommendationCounterCache.first(name: player.name.downcase)

    count = recommendations ? recommendations.recommendations - recommendations.noobs : 0
    if count.zero? || count.negative?
      broadcast_message("[MOBIUS] #{player.name} does not have any recommendations yet.")
    else
      broadcast_message("[MOBIUS] #{player.name} has #{count} recommendations.")
    end
  end
end