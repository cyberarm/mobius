mobius_plugin(name: "GameDirector", database_name: "game_director", version: "0.0.1") do
  on(:start) do
    @spectators = {}
  end

  on(:map_loaded) do
    @spectators = {}
  end

  command(:conyard, arguments: 1..2, help: "!conyard <nickname> [<repair amount>] - Make player a living Construction Yard that repairs their teams buildings by <repair amount> until they're killed.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    repair_amount = 3.5

    begin
      repair_amount = Float(command.arguments.last)
    rescue ArgumentError
    end

    if player
      if repair_amount.positive?
        RenRem.cmd("attachscript #{player.id} dp88_buildingScripts_functionRepairBuildings #{repair_amount},None,false")
        broadcast_message("[GameDirector] #{player.name} has been made a living Construction Yard!")
      else
        page_player(command.issuer, "Repair amount must be positive, got #{repair_amount.round(4)}")
      end
    else
      page_player(command.issuer, "Failed to find player.")
    end
  end

  command(:remix, arguments: 0, help: "!remix NOW - Remix teams", groups: [:admin, :mod]) do |command|
    if command.arguments.first == "NOW"
      log "#{command.issuer.name} remixed teams"
      remix_teams
      broadcast_message("[GameDirector] Teams have been remixed")
    else
      page_player(command.issuer, "Use !remix NOW, to truely remix teams!")
    end
  end

  command(:gameover, arguments: 1, help: "!gameover NOW", groups: [:admin, :mod, :director]) do |command|
    if command.arguments.first == "NOW"
      log "#{command.issuer.name} ended the game"
      RenRem.cmd("gameover")
    else
      page_player(command.issuer, "Use !gameover NOW, to truely end the game!")
    end
  end

  command(:setnextmap, aliases: [:snm], arguments: 1, help: "!setnextmap <mapname>", groups: [:admin, :mod, :director]) do |command|
    maps = ServerConfig.installed_maps.select do |map|
      map.downcase.include?(command.arguments.first.downcase)
    end

    # Exact match
    exact_match = maps.find { |map| map.downcase == command.arguments.first.downcase }
    maps = [exact_match] if maps.count > 1 && exact_match

    if maps.count > 1
      page_player(command.issuer, "More than one map matched search, found: #{maps.join(', ')}")
    elsif maps.count.zero?
      page_player(command.issuer, "No map matched: #{command.arguments.first}")
    else
      original_map = ServerConfig.rotation.rotate(ServerStatus.get(:current_map_number) + 1)&.first
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

  command(:time, arguments: 1, help: "!time 5[{s,m,h}]", groups: [:admin, :mod, :director]) do |command|
    match_data = command.arguments.first.downcase.match(/(\d+)([smh])/)

    time = -1
    unit = "s"

    if match_data
      time = match_data[1].to_i
      unit = match_data[2]
    else
      begin
        time = Integer(command.arguments.first)
      rescue ArgumentError
        time = -1
      end
    end

    hardcap = 2 * 60 * 60 # 2 hours

    if (unit == "s" && time > hardcap) || (unit == "m" && time * 60 > hardcap) || (unit == "h" && time * 60 * 60 > hardcap)
      log "Player #{command.issuer.name} attempted to set the game clock to #{match_data ? match_data[0] : "#{time}s"}"
      page_player(command.issuer, "Game clock may not be set greater than 2 hours! Overriding to 2 hours.")

      # Override input
      time = 2
      unit = "h"
    end

    if time <= 0
      page_player(command.issuer, "Time must be greater than 0!")
    else
      case unit.downcase
      when "s"
        RenRem.cmd("time #{time}")
        log "#{command.issuer.name} has set the game clock to #{time} seconds"
        broadcast_message("[GameDirector] #{command.issuer.name} has set the game clock to #{time} seconds")
      when "m"
        RenRem.cmd("time #{time * 60}")
        log "#{command.issuer.name} has set the game clock to #{time} minutes"
        broadcast_message("[GameDirector] #{command.issuer.name} has set the game clock to #{time} minutes")
      when "h"
        RenRem.cmd("time #{time * 60 * 60}")
        log "#{command.issuer.name} has set the game clock to #{time} hours"
        broadcast_message("[GameDirector] #{command.issuer.name} has set the game clock to #{time} hours")
      else
        page_player(command.issuer, "Time unit must be s for seconds, m for minutes, and h for hours. Example: !time 15m")
      end
    end
  end

  command(:force_team_change, aliases: [:ftc], arguments: 1..2, help: "!force_team_change <nickname> [<team name or id>]", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    team = command.arguments.last

    if player && team.to_s.empty?
      team = (player.team + 1) % 2
    else
      begin
        team = Integer(team)
      rescue ArgumentError
        team = Teams.id_from_name(team)
        team = team[:id] if team
      end
    end

    if player
      if team.is_a?(Integer)
        broadcast_message("[GameDirector] Player #{player.name} has changed teams")
        player.set_value(:manual_team, true)
        player.change_team(team)
      else
        page_player(command.issuer, "Failed to detect team for: #{command.arguments.last}, got #{team}, try again.")
      end
    else
      page_player(command.issuer, "Player is not in game or name is not unique!")
    end
  end

  command(:revive, arguments: 2, help: "!revive <team> <building preset>", groups: [:admin, :mod]) do |command|
    team = command.arguments.first
    preset = command.arguments.last

    begin
      team = Integer(team)
    rescue ArgumentError
      team = Teams.id_from_name(team)
      team = team[:id] if team
    end

    if team.is_a?(Integer)
      page_player(command.issuer, "Attempting to revive building for team #{Teams.name(team)} from preset: #{preset}")
      RenRem.cmd("revivebuildingbypreset #{team} #{preset}")
    else
      page_player(command.issuer, "Failed to detect team for: #{command.arguments.first}, got #{team}, try again.")
    end
  end

  command(:spawn, arguments: 2, help: "!spawn <z> <vehicle preset>", groups: [:admin, :mod]) do |command|
    z = Integer(command.arguments.first)
    preset = command.arguments.last

    page_player(command.issuer, "Attempting to spawn vehicle from preset: #{preset}")
    RenRem.cmd("SpawnVehicle #{command.issuer.id} #{z} #{preset}")
  end

  command(:spectate, arguments: 0..1, help: "!spectate [<nickname>]", groups: [:admin, :mod]) do |command|
    nickname = command.arguments.first
    player = PlayerData.player(PlayerData.name_to_id(nickname, exact_match: false))
    spectating = @spectators[player ? player.name : command.issuer.name]

    spectate_command = ServerConfig.scripts_version < 5.0 ? "spectate" : "toggle_spectator"

    if player
      if spectating
        @spectators.delete(player.name)
        spectating = false
      else
        spectating = @spectators[player.name] = true
      end

      RenRem.cmd("#{spectate_command} #{player.id}")
      page_player(player, "You are #{spectating ? 'now' : 'no longer' } spectating.")
      page_player(command.issuer, "#{player.name} is #{spectating ? 'now' : 'no longer' } spectating.")
    elsif nickname.to_s.empty?
      if spectating
        @spectators.delete(command.issuer.name)
        spectating = false
      else
        spectating = @spectators[command.issuer.name] = true
      end

      RenRem.cmd("#{spectate_command} #{command.issuer.id}")
      page_player(command.issuer, "You are #{spectating ? 'now' : 'no longer' } spectating.")
    else
      page_player(command.issuer, "Player is not in game or name is not unique!")
    end
  end

  command(:setspeed, arguments: 0..2, help: "!setspeed [<nickname>] speed - 4.x only", groups: [:admin, :mod]) do |command|
    unless ServerConfig.scripts_version < 5.0
      page_player(command.issuer, "!setspeed only usable on 4.x servers.")
      next # return, but for procs
    end

    on_self = command.arguments.last.to_s.empty?
    nickname = on_self ? nil : command.arguments.first
    player = on_self ? nil : PlayerData.player(PlayerData.name_to_id(nickname, exact_match: false))
    speed = on_self ? command.arguments.first.to_f : command.arguments.last.to_f
    # spectating = @spectators[player ? player.name : command.issuer.name]

    if player
      RenRem.cmd("setspeed #{player.id} #{speed}")
      page_player(player, "Your spectate speed is now #{speed}")
      page_player(command.issuer, "#{player.name} spectate speed is now #{speed}")
    elsif nickname.to_s.empty?
      RenRem.cmd("setspeed #{command.issuer.id} #{speed}")
      page_player(command.issuer, "spectate speed is now #{speed}")
    else
      page_player(command.issuer, "Player is not in game or name is not unique!")
    end
  end

  command(:nextmap, aliases: [:n, :next], arguments: 0, help: "!nextmap") do |command|
    map = ServerConfig.rotation.rotate(ServerStatus.get(:current_map_number) + 1)&.first

    broadcast_message(map)
  end

  command(:rotation, aliases: [:r, :rot], arguments: 0, help: "!rotation") do |command|
    maps = ServerConfig.rotation.rotate((ServerStatus.get(:current_map_number) + 1))

    maps.each_slice(6) do |slice|
      broadcast_message(
        slice.join(", ")
      )
    end
  end

  command(:ping, arguments: 0..1, help: "!ping [<nickname>]") do |command|
    if command.arguments.first.empty?
      player = PlayerData.player(PlayerData.name_to_id(command.issuer.name))

      if player
        broadcast_message("#{command.issuer.name}'s ping: #{player.ping}ms")
      else
        broadcast_message("Failed to find player.")
      end
    else
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        broadcast_message("#{player.name}'s ping: #{player.ping}ms")
      else
        broadcast_message("Player not in game or name is not unique!")
      end
    end
  end

  command(:vlimit, arguments: 0, help: "!vlimit - Reports vehicle limit") do |command|
    broadcast_message("Vehicle limit is #{ServerStatus.get(:vehicle_limit)} vehicles.")
  end

  command(:alimit, arguments: 0, help: "!alimit - Reports air vehicle limit") do |command|
    broadcast_message("Air vehicle limit is #{ServerStatus.get(:vehicle_air_limit)} aircraft.")
  end

  command(:nlimit, arguments: 0, help: "!nlimit - Reports naval vehicle limit") do |command|
    broadcast_message("Naval vehicle limit is #{ServerStatus.get(:vehicle_naval_limit)} vessels.")
  end

  command(:mlimit, arguments: 0, help: "!mlimit - Reports mine limit") do |command|
    broadcast_message("Mine limit is #{ServerStatus.get(:mine_limit)} mines.")
  end

  command(:svlimit, arguments: 1, help: "!svlimit <limit> - Set vehicle limit", groups: [:admin, :mod, :director]) do |command|
    limit = begin
      Integer(command.arguments.first)
    rescue ArgumentError
      -1
    end

    if limit.negative?
      message_player(command.issuer, "Invalid value for limit, must be a non-negative number.")
    else
      renrem_cmd("vlimit #{limit}")
      ServerStatus.update_vehicle_limit(limit)
      broadcast_message("Vehicle limit is now #{limit} vehicles.")
    end
  end

  command(:salimit, arguments: 1, help: "!salimit <limit> - Set air vehicle limit", groups: [:admin, :mod, :director]) do |command|
    limit = begin
      Integer(command.arguments.first)
    rescue ArgumentError
      -1
    end

    if limit.negative?
      message_player(command.issuer, "Invalid value for limit, must be a non-negative number.")
    else
      renrem_cmd("alimit #{limit}")
      ServerStatus.update_vehicle_air_limit(limit)
      broadcast_message("Air vehicle limit is now #{limit} aircraft.")
    end
  end

  command(:snlimit, arguments: 1, help: "!snlimit <limit> - Set naval vehicle limit", groups: [:admin, :mod, :director]) do |command|
    limit = begin
      Integer(command.arguments.first)
    rescue ArgumentError
      -1
    end

    if limit.negative?
      message_player(command.issuer, "Invalid value for limit, must be a non-negative number.")
    else
      renrem_cmd("nlimit #{limit}")
      ServerStatus.update_vehicle_naval_limit(limit)
      broadcast_message("Naval vehicle limit is now #{limit} vessels.")
    end
  end

  command(:smlimit, arguments: 1, help: "!smlimit <limit> - Set mine limit", groups: [:admin, :mod, :director]) do |command|
    limit = begin
      Integer(command.arguments.first)
    rescue ArgumentError
      -1
    end

    if limit.negative?
      message_player(command.issuer, "Invalid value for limit, must be a non-negative number.")
    else
      renrem_cmd("mlimit #{limit}")
      ServerStatus.update_mine_limit(limit)
      broadcast_message("Mine limit now #{limit} mines.")
    end
  end

  vote(:cyclemap, arguments: 0, description: "Vote to end match and cycle map", groups: [:admin, :mod, :director]) do |vote|
    if vote.validate?
      true
    elsif vote.commit?
      broadcast_message("[GameDirector] Match will end in 10 seconds...")
      RenRem.cmd("time 10")
    end
  end
end
