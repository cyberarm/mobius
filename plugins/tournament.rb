mobius_plugin(name: "Tournament", version: "0.0.1") do
  def change_players(ghost: false)
    return unless @tournament
    return unless @preset

    PlayerData.player_list.each do |player|
      RenRem.cmd("eject #{player.id}")
      if ghost
        RenRem.cmd("ChangeChar #{player.id} #{player.team.zero? ? @team_0_ghost : @team_1_ghost}")
      else
        RenRem.cmd("ChangeChar #{player.id} #{@preset}")
      end
    end
  end

  on(:start) do
    @tournament = false
    @last_man_standing = false
    @preset = nil

    @team_0_ghost = Config.tournament[:team_0_ghost]
    @team_1_ghost = Config.tournament[:team_1_ghost]
  end

  on(:created) do |hash|
    if hash[:type].downcase.strip == "soldier" && (@tournament || @last_man_standing)
      if hash[:preset] != @team_0_ghost || hash[:preset] != @team_1_ghost
        change_players if @tournament

        change_players(ghost: true) if @last_man_standing
      end
    end
  end

  command(:tournament, arguments: 0..1, help: "", groups: [:admin, :mod, :director]) do |command|
    if (preset = command.agruments.first)
      @tournament = true
      @preset = preset

      broadcast_message("[MOBIUS] Tournament mode has been activated!")

      change_players
    else
      @tournament = false
      @preset = nil

      broadcast_message("[MOBIUS] Tournament mode has been deactivated!")
    end
  end

  command(:lastmanstanding, arguments: 0..1, help: "", groups: [:admin, :mod, :director]) do |command|
    if (preset = command.agruments.first)
      @last_man_standing = true
      @preset = preset

      broadcast_message("[MOBIUS] Last Man Standing mode has been activated!")

      change_players
    else
      @last_man_standing = false
      @preset = nil

      broadcast_message("[MOBIUS] Last Man Standing mode has been deactivated!")
    end
  end
end
