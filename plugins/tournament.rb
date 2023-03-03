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

    raise "team_0_ghost_preset is not set in config!" unless @team_0_ghost_preset
    raise "team_1_ghost_preset is not set in config!" unless @team_1_ghost_preset
    raise "infected_preset is not set in config!" unless @infected_preset

    @recent_kills = []
    @ghost_players = []
    @infected_players = []
  end

  def infection_survivor_count
    PlayerData.players_by_team(1).count
  end

  def ghost_count
    PlayerData.player_list.select { |ply| @ghost_players[ply.id] }.count
  end

  def the_last_man_standing
    PlayerData.player_list.find { |ply| @ghost_players[ply.id].nil? }
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
        page_player(player.name, "[Tournament] Group up! The infected will try to hunt you all down.")
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

      if just_killed
        @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
      end

      if player
        if @tournament
          change_player(player: player)
        end

        if @last_man_standing && (hash[:preset].downcase != @team_0_ghost_preset.downcase && hash[:preset].downcase != @team_1_ghost_preset.downcase)
          if just_killed
            just_ghosted = @ghost_players[player.id].nil?

            @ghost_players[player.id] = true
            change_player(player: player, ghost: true)
            player.change_team(3, kill: false)

            if just_ghosted
              broadcast_message("[Tournament] #{player.name} has become a ghost!")
              page_player(player.name, "You've become a ghost, go forth and haunt the living!")
            end
          else
            change_player(player: player) unless @ghost_players[player.id]
          end
        end

        if @infection && hash[:preset].downcase != @infected_preset.downcase
          is_infected = @infected_players[player.id]

          if just_killed || is_infected
            just_infected = @infected_players[player.id].nil? || @infected_players[player.id] == 0
            log "Player: #{player.name} just infected? #{just_infected}"

            @infected_players[player.id] = true
            player.change_team(0)
            change_player(player: player, infected: true)

            if just_infected && infection_survivor_count.positive?
              broadcast_message("[Tournament] #{player.name} has been infected, there are only #{infection_survivor_count} survivors left!")
              page_player(player.name, "You have been infected, hunt down the #{infection_survivor_count} survivors!")
              log("#{player.name} has been infected!")

              if infection_survivor_count == 1
                PlayerData.players_by_team(1).each do |ply|
                  page_player(ply.name, "You are the last survivor!")
                end
              end
            end
          else
            unless is_infected
              player.change_team(1)
              change_player(player: player)
            end
          end
        end
      end
    end
  end

  on(:killed) do |hash|
    if hash[:killed_type].downcase == "soldier" &&
       hash[:killer_preset].downcase != "(null)" &&
       (@tournament || @last_man_standing || @infection)
      @recent_kills << hash
    end
  end

  on(:tick) do
    if @tournament || @last_man_standing || @infection
      if @last_man_standing
        if ghost_count == PlayerData.player_list.count - 1
          broadcast_message("[Tournament] #{the_last_man_standing.name} won as the Last Man Standing!")
          log("#{the_last_man_standing.name} won as the Last Man Standing!")

          reset
        elsif PlayerData.players_by_team(0).count.zero? || PlayerData.players_by_team(1).count.zero?
          winning_team = if PlayerData.players_by_team(0).count.zero?
                           Teams.name(1)
                         else
                           Teams.name(0)
                         end

          broadcast_message("[Tournament] The #{winning_team} have won the Last Man Standing!")

          reset
        end

      elsif @infection
        if infection_survivor_count.zero? # == ServerStatus.total_players
          broadcast_message("[Tournament] All players have been infected!")
          log("All players have been infected!")

          reset
        end
      end
    end
  end

  command(:tournament, arguments: 0..1, help: "!tournament [<soldier_preset>] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first

    if preset.empty?
      reset

      broadcast_message("[Tournament] Tournament mode has been deactivated!")
      log("Tournament mode has been deactivated!")
    else
      @tournament = true
      @last_man_standing = false
      @infection = false
      @preset = preset

      broadcast_message("[Tournament] Tournament mode has been activated!")
      log("Tournament mode has been activated!")

      PlayerData.player_list.each do |player|
        RenRem.cmd("kill #{player.id}")
      end
    end
  end

  command(:lastmanstanding, arguments: 0..1, help: "!lastmanstanding [<soldier_preset>] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>, on death they become ghosts.", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first

    if preset.empty?
      reset

      broadcast_message("[Tournament] Last Man Standing mode has been deactivated!")
      log("Last Man Standing mode has been deactivated!")
    else
      @last_man_standing = true
      @tournament = false
      @infection = false
      @preset = preset

      broadcast_message("[Tournament] Last Man Standing mode has been activated!")
      log("Last Man Standing mode has been activated!")

      PlayerData.player_list.each do |player|
        RenRem.cmd("kill #{player.id}")
      end
    end
  end

  command(:infection, arguments: 0..2, help: "!infection [<hunter_preset>, [<infected_preset>]] - Evicts all players from vehicles and forces everyone to play as <hunter_preset> and <infected_preset>, on death they become infected.", groups: [:admin, :mod, :director]) do |command|
    hunter_preset = command.arguments.first
    infected_preset = command.arguments.last

    if hunter_preset.to_s.empty?
      reset

      broadcast_message("[Tournament] Infection mode has been deactivated!")
      log("Infection mode has been deactivated!")
    else
      @infection = true
      @last_man_standing = false
      @tournament = false
      @preset = hunter_preset

      @infected_preset = infected_preset if !infected_preset.to_s.empty?

      broadcast_message("[Tournament] Infection mode has been activated!")
      log("Infection mode has been activated!")

      infected = (ServerStatus.total_players / 4.0).ceil
      log "Infecting #{infected} players..."

      PlayerData.player_list.shuffle.shuffle.shuffle.each_with_index do |player, i|
        if i < infected
          @infected_players[player.id] = 0
          RenRem.cmd("kill #{player.id}")
          player.change_team(0)
        else
          RenRem.cmd("kill #{player.id}")
          player.change_team(1)
          page_player(player.name, "Group up! The infected will try to hunt you all down!")
        end
      end
    end
  end

  command(:infect, arguments: 1, help: "!infect <nickname> - Manually infect player.", groups: [:admin, :mod]) do |command|
    if @infection
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        @infected_players[player.id] = true
        player.change_team(0)
        change_player(player: player, infected: true)
        page_player(player.name, "You have been infected, hunt down the #{infection_survivor_count} survivors!")
        log("#{player.name} has been manually infected by #{command.issuer.name}")
      else
        page_player(command.issuer.name, "Player #{command.arguments.first} was not found ingame, or is not unique.")
      end
    else
      page_player(command.issuer.name, "Infection mode is not enabled.")
    end
  end
end
