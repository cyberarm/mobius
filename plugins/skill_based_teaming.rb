mobius_plugin(name: "SkillBasedTeaming", database_name: "skill_based_teaming", version: "0.0.1") do
  on(:maploaded) do |mapname|
    next unless Config.remix_teams_by_skill

    log "Assigning players to teams based on skill..."

    team_zero, team_one, team_zero_rating, team_one_rating = Teams.skill_sort_teams
    Teams.team_first_picking = Teams.team_first_picking.zero? ? 1 : 0

    team_zero.each do |player|
      log "Assigning #{player.name} to team #{Teams.name(0)}"
      player.set_value(:skill_assigned_team, 0)
    end

    team_one.each do |player|
      log "Assigning #{player.name} to team #{Teams.name(1)}"
      player.set_value(:skill_assigned_team, 1)
    end

    log "Team skill difference: #{(team_one_rating - team_zero_rating).round(2)}"
  end

  on(:created) do |object|
    next unless Config.remix_teams_by_skill

    # Assign player to team if using skill based teaming
    player = PlayerData.player(PlayerData.name_to_id(object[:name]))

    if player
      assigned_team = player.value(:skill_assigned_team)

      if assigned_team
        player.delete_value(:skill_assigned_team)

        if assigned_team && player.team != assigned_team
          log "Assigned #{player.name} to team #{Teams.name(assigned_team)}"
          player.change_team(assigned_team)
        else
          log "#{player.name} already on assigned team #{Teams.name(assigned_team)}"
        end
      end
    end
  end
end
