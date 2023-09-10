mobius_plugin(name: "AFK", database_name: "afk", version: "0.0.1") do
  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    @inactive_warning_timeout = (config[:inactive_warning_timeout_in_minutes] || 7)  * 60 # minutes
    @inactive_kick_timeout    = (config[:inactive_kick_timeout_in_minutes]    || 10) * 60 # minutes

    @player_last_activity = {}
    @player_afk = {}

    # Initialize the things!
    PlayerData.player_list.each do |player|
      player_active!(player)
    end
  end

  on(:tick) do
    PlayerData.player_list.each do |player|
      # Possibly handle edge case where a glitch causes a player to still appear in PlayerData when they lagged out or something...
      next unless @player_last_activity[player.name]

      if (monotonic_time - @player_last_activity[player.name]) > @inactive_warning_timeout && !@player_afk[player.name]
        player_afk!(player)
      elsif (monotonic_time - @player_last_activity[player.name]) > @inactive_kick_timeout && @player_afk[player.name]
        kick_afk_player!(player)
      end
    end
  end

  on(:player_joined) do |player|
    player_active!(player)
  end

  on(:player_left) do |player|
    afk_cleanup!(player)
  end

  on(:chat) do |player, message|
    player_active!(player)
  end

  on(:team_chat) do |player, message|
    player_active!(player)
  end

  on(:enter_vehicle) do |object|
    player_object = object[:_player_object]
    next unless player_object && player_object[:name]

    player = PlayerData.player(PlayerData.name_to_id(player_object[:name]))
    next unless player

    player_active!(player)
  end

  on(:exit_vehicle) do |object|
    player_object = object[:_player_object]
    next unless player_object && player_object[:name]

    player = PlayerData.player(PlayerData.name_to_id(player_object[:name]))
    next unless player

    player_active!(player)
  end

  on(:purchased) do |object, raw|
    player_object = object[:_player_object]
    next unless player_object && player_object[:name]

    player = PlayerData.player(PlayerData.name_to_id(player_object[:name]))
    next unless player

    player_active!(player)
  end

  on(:damaged) do |object, raw|
    player = object[:_damager_player_object]
    next unless player

    player_active!(player)
  end

  def player_active!(player)
    last_activity = @player_last_activity[player.name]
    @player_last_activity[player.name] = monotonic_time

    was_afk = @player_afk[player.name]
    @player_afk.delete(player.name)

    if was_afk
      page_player(player.name, "[MOBIUS] You you are no longer marked as AFK. Welcome back!")
      log "#{player.name} is no longer marked as AFK. Appeared AFK for #{(monotonic_time - last_activity.to_i).round(2)}s"
    end
  end

  def player_afk!(player)
    @player_afk[player.name] = true
    page_player(player.name, "[MOBIUS] You have been marked as AFK, you will be kicked soon unless you become active.")
    log "#{player.name} has been marked as AFK."
  end

  def kick_afk_player!(player)
    afk_cleanup!(player)

    ip = player.address.split(";").first
    reason = "AFK"
    moderator = "[MOBIUS:AFK]"
    kick = Database::ModeratorAction.create(
      name: player.name.downcase,
      ip: ip,
      serial: "00000000000000000000000000000000",
      moderator: moderator,
      reason: reason,
      action: Mobius::MODERATOR_ACTION[:kick]
    )

    Database::Log.create(
      log_code: Mobius::LOG_CODE[:kicklog],
      log: "[KICK] #{player.name} (#{ip}) was kicked by [MOBIUS:AFK] for \"#{reason}\". (ID #{kick.id})"
    )

    kick_player!(player.name, reason)

    broadcast_message("[MOBIUS] #{player.name} has been kicked due to being AFK.")
    log "#{player.name} has been kicked due to being AFK."
  end

  def afk_cleanup!(player)
    @player_last_activity.delete(player.name)
    @player_afk.delete(player.name)
  end
end
