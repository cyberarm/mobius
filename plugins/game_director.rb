mobius_plugin(name: "GameDirector", version: "0.0.1") do
  # TODO: Store map index and name to restore later if needed
  on(:start) do
  end

  # TODO: Restore original map rotation
  on(:map_loaded) do
  end

  command(:gameover, arguments: 1, help: "!gameover NOW", groups: [:admin, :mod, :director]) do |command|
    if command.arguments.first == "NOW"
      log "#{command.issuer.name} ended the game"
      RenRem.cmd("gameover")
    else
      RenRem.cmd("ppage #{command.issuer.id} Use !gameover NOW to truely end the game")
    end
  end

  command(:setnextmap, arguments: 1, help: "!setnextmap <mapname>", groups: [:admin, :mod, :director]) do |command|
    # message_player(command.issuer.name, "Not yet implemented!")

    maps = ServerConfig.installed_maps.select do |map|
      map.downcase.include?(command.arguments.first.downcase)
    end

    if maps.count > 1
      page_player(command.issuer.name, "More than one map matched search, found: #{maps.join(', ')}")
    elsif maps.count.zero?
      page_player(command.issuer.name, "No map matched: #{command.arguments.first}")
    else
      original_map = ServerConfig.rotation[ServerStatus.get(:current_map_number)]
      array_index = ServerConfig.rotation.index(original_map)

      RenRem.cmd("mlistc #{array_index} #{maps.first}")

      ServerConfig.data[:nextmap_changed_id] = array_index
      ServerConfig.data[:nextmap_changed_mapname] = original_map

      # Update rotation
      log "Switching #{original_map} with #{maps.first}"
      ServerConfig.rotation[array_index] = maps.first

      broadcast_message("[GameDirector] Set next map to #{maps.first}")
    end
  end

  command(:maps, arguments: 0, help: "!maps", groups: [:admin, :mod, :director]) do |command|
    maps = ServerConfig.installed_maps

    maps.each_slice(6) do |slice|
      broadcast_message(
        slice.join(", ")
      )
    end
  end

  command(:time, arguments: 1, help: "!time 5m", groups: [:admin, :mod, :director]) do |command|
    match_data = command.arguments.first.match(/(\d+)([smh])/)

    time = match_data[1].to_i
    unit = match_data[2]

    hardcap = 2 * 60 * 60 # 2 hours

    if time <= 0
      page_player(command.issuer.name, "Time must be greater than 0!")
    elsif (unit == "s" && time >= hardcap) || (unit == "m" && time * 60 >= hardcap)
      log "Player #{command.issuer.name} attempted to set the game clock to #{match_data[0]}"
      page_player(command.issuer.name, "Game clock may not be set greater than 2 hours!")
    else
      case unit
      when "s"
        RenRem.cmd("time #{time}")
        log "#{command.issuer.name} has set the game clock to #{time} seconds"
        broadcast_message("[GameDirector] #{command.issuer.name} has set the game clock to #{time} seconds")
      when "m"
        RenRem.cmd("time #{time * 60}")
        log "#{command.issuer.name} has set the game clock to #{time} minutes"
        broadcast_message("[GameDirector] #{command.issuer.name} has set the game clock to #{time} minutes")
      else
        page_player(command.issuer.name, "Time unit must be s for seconds and m for minutes. Example: !time 15m")
      end
    end
  end

  command(:force_team_change, arguments: 2, help: "!force_team_change <nickname> <team name or id>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    team = command.arguments.last

    begin
      team = Integer(team)
    rescue ArgumentError
      team = Teams.id_from_name(team)
      team = team[:id] if team
    end

    if player
      if team.is_a?(Integer)
        broadcast_message("[GameDirector] Player #{player.name} has changed teams")
        RenRem.cmd("team2 #{player.id} #{team}")
      else
        page_player(command.issuer.name, "Failed to detect team for: #{command.arguments.last}, got #{team}, try again.")
      end
    else
      page_player(command.issuer.name, "Player is not in game or name is not unique!")
    end
  end

  command(:nextmap, arguments: 0, help: "!nextmap") do |command|
    map = ServerConfig.rotation[ServerStatus.get(:current_map_number) + 1]

    broadcast_message(map)
  end

  command(:rotation, arguments: 0, help: "!rotation") do |command|
    maps = ServerConfig.rotation.rotate((ServerStatus.get(:current_map_number) + 1))

    maps.each_slice(6) do |slice|
      broadcast_message(
        slice.join(", ")
      )
    end
  end

  # FIXME:
  command(:donate, arguments: 2, help: "!donate <nickname> <amount>") do |command|
    broadcast_message("Not implemented, yet.")
  end

  # FIXME:
  command(:team_donate, arguments: 1, help: "!donate <amount>") do |command|
    broadcast_message("Not implemented, yet.")
  end

  # FIXME:
  command(:stuck, arguments: 0, help: "Become unstuck, maybe.") do |command|
    broadcast_message("Not implemented, yet.")
  end

  command(:killme, arguments: 0, help: "Kill yourself") do |command|
    RenRem.cmd("kill #{command.issuer.id}")

    broadcast_message("#{command.issuer.name} has respawned")
  end

  command(:ping, arguments: 0, help: "!ping") do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.issuer.name))

    broadcast_message("#{command.issuer.name}'s ping: #{player&.ping}ms")
  end

  command(:player_ping, arguments: 1, help: "!player_ping <nickname>") do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exect_match: false))

    if player
      broadcast_message("#{player.name}'s ping: #{player.ping}ms")
    else
      broadcast_message("Player not in game or query is not unique!")
    end
  end
end
