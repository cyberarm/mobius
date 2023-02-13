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

  on(:start) do
    @tournament = false
    @last_man_standing = false
    @infection = false
    @preset = nil

    @team_0_ghost_preset = Config.tournament[:team_0_ghost_preset]
    @team_1_ghost_preset = Config.tournament[:team_1_ghost_preset]

    @infected_preset = Config.tournament[:infected_preset]
  end

  on(:map_loaded) do |map|
    @tournament = false
    @last_man_standing = false
    @infection = false
    @preset = nil

    @team_0_ghost_preset = Config.tournament[:team_0_ghost_preset]
    @team_1_ghost_preset = Config.tournament[:team_1_ghost_preset]

    @infected_preset = Config.tournament[:infected_preset]
  end

  on(:created) do |hash|
    if hash[:type].downcase.strip == "soldier" && (@tournament || @last_man_standing || @infection) && hash[:preset] != @preset
      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

      if player
        if @tournament
          change_player(player: player)
        end

        if @last_man_standing && (hash[:preset] != @team_0_ghost_preset && hash[:preset] != @team_1_ghost_preset)
          change_player(player: player, ghost: true)
        end

        if @infection && hash[:preset] != @infected_preset
          RenRem.cmd("team2 #{player.id} 0")
          change_player(player: player, infected: true)
        end
      end
    end
  end

  command(:tournament, arguments: 0..1, help: "!tournament [<soldier_preset>] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first

    if preset.empty?
      @tournament = false
      @last_man_standing = false
      @infection = false
      @preset = nil

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
      @last_man_standing = false
      @tournament = false
      @infection = false
      @preset = nil

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
      @last_man_standing = false
      @tournament = false
      @infection = false
      @preset = nil

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
        RenRem.cmd("team2 #{player.id} 1")
      end
      change_players

      infected = (ServerStatus.total_players / 6.0).ceil

      PlayerData.player_list.sample(infected).each do |player|
        RenRem.cmd("team2 #{player.id} 0")
        change_player(player: player, infected: true)
      end
    end
  end
end
