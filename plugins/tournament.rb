mobius_plugin(name: "Tournament", version: "0.0.1") do
  def change_player(player:, ghost: false, infected: false)
    return unless @tournament || @last_man_standing || @infection
    return unless @preset

    RenRem.cmd("eject #{player.id}")
    if ghost
      RenRem.cmd("ChangeChar #{player.id} #{player.team.zero? ? @team_0_ghost_preset : @team_1_ghost_preset}")
    elsif infected
      RenRem.cmd("ChangeChar #{player.id} #{@infected_preset}")
    else
      RenRem.cmd("ChangeChar #{player.id} #{@preset}")
    end
  end

  def change_players(ghost: false, infected: false)
    return unless @tournament || @last_man_standing || @infection
    return unless @preset

    PlayerData.player_list.each do |player|
      change_player(player: player, ghost: ghost, infected: infected)
    end
  end

  def just_killed?(player)
    @recent_kills.find { GameLog.current_players[player.name.downcase] }
  end

  def reset
    @tournament = false
    @last_man_standing = false
    @infection = false
    @preset = nil

    @team_0_ghost_preset = Config.tournament[:team_0_ghost_preset]
    @team_1_ghost_preset = Config.tournament[:team_1_ghost_preset]

    @infected_preset = Config.tournament[:infected_preset]

    @recent_kills = []
    @infectioned_players = []
  end

  on(:start) do
    reset
  end

  on(:map_loaded) do |map|
    reset
  end

  on(:player_joined) do |player|
    if (@tournament || @last_man_standing || @infection)
      change_player(player: player) if @tournament

      change_player(player: player) if @last_man_standing

      if @infection
        player.change_team(1)
        change_player(player: player)
      end
    end
  end

  on(:player_left) do |player|
    @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
  end

  on(:created) do |hash|
    if hash[:type].downcase.strip == "soldier" && (@tournament || @last_man_standing || @infection) && hash[:preset].downcase != @preset.downcase
      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))
      just_killed = player && just_killed?(player)

      if player
        if @tournament
          change_player(player: player)
        end

        if @last_man_standing && (hash[:preset].downcase != @team_0_ghost_preset.downcase && hash[:preset].downcase != @team_1_ghost_preset.downcase)
          if just_killed
            change_player(player: player, ghost: true)
          else
            change_player(player: player)
          end
        end

        if @infection && hash[:preset].downcase != @infected_preset.downcase
          if just_killed
            @infectioned_players[player.id] = true
            player.change_team(0)
            change_player(player: player, infected: true)
          else
            unless @infectioned_players[player.id]
              player.change_team(1)
              change_player(player: player)
            end
          end
        end

        if just_killed
          @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
        end
      end
    end
  end

  on(:killed) do |hash|
    @recent_kills << hash if hash[:killed_type].downcase == "soldier" && (@tournament || @last_man_standing || @infection)
  end

  command(:tournament, arguments: 0..1, help: "!tournament [<soldier_preset>] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first

    if preset.empty?
      reset

      broadcast_message("[Tournament] Tournament mode has been deactivated!")
    else
      @tournament = true
      @last_man_standing = false
      @infection = false
      @preset = preset

      broadcast_message("[Tournament] Tournament mode has been activated!")

      change_players
    end
  end

  command(:lastmanstanding, arguments: 0..1, help: "!lastmanstanding [<soldier_preset>] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>, on death they become ghosts.", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first

    if preset.empty?
      reset

      broadcast_message("[Tournament] Last Man Standing mode has been deactivated!")
    else
      @last_man_standing = true
      @tournament = false
      @infection = false
      @preset = preset

      broadcast_message("[Tournament] Last Man Standing mode has been activated!")

      change_players
    end
  end

  command(:infection, arguments: 0..2, help: "!infection [<hunter_preset>, [<infected_preset>]] - Evicts all players from vehicles and forces everyone to play as <hunter_preset> and <infected_preset>, on death they become infected.", groups: [:admin, :mod, :director]) do |command|
    hunter_preset = command.arguments.first
    infected_preset = command.arguments.last

    if hunter_preset.to_s.empty?
      reset

      @infected_preset = Config.tournament[:infected_preset]

      broadcast_message("[Tournament] Infection mode has been deactivated!")
    else
      @infection = true
      @last_man_standing = false
      @tournament = false
      @preset = hunter_preset

      if hunter_preset != infected_preset && !infected_preset.to_s.empty?
        @infected_preset = infected_preset
      end

      broadcast_message("[Tournament] Infection mode has been activated!")

      PlayerData.player_list.each do |player|
        player.change_team(1)
      end
      change_players

      infected = (ServerStatus.total_players / 6.0).ceil

      PlayerData.player_list.sample(infected).each do |player|
        @infectioned_players[player.id] = true
        player.change_team(0)
        change_player(player: player, infected: true)
      end
    end
  end

  command(:infect, arguments: 1, help: "!infect <nickname> - Manually infect player.", groups: [:admin, :mod]) do |command|
    if @infection
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        @infectioned_players[player.id] = true
        player.change_team(0)
        change_player(player: player, infected: true)
      else
        page_player(command.issuer.name, "Player #{command.arguments.first} was not found ingame, or is not unique.")
      end
    else
      page_player(command.issuer.name, "Infection mode is not enabled.")
    end
  end
end
