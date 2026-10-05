mobius_plugin(name: "BadHarvester", database_name: "bad_harvester", version: "0.0.1") do
  def bad_harvester!
    @harvesters.each do |team_id, hash|
      hash[:counter] += 1

      if hash[:counter] >= hash[:interval_seconds]
        hash[:counter] = 0

        players = PlayerData.players_by_object_team(team_id)
        if players
          message_team(team_id, "[BadHarvester] Receiving additional resources...")
          PlayerData.players_by_object_team(team_id)&.each do |player|
            SSGM.cmd("credits #{player.id} #{hash[:credits_per_player]}")
          end
        end
      end
    end
  end

  on(:start) do
    @harvesters = {}
  end

  on(:map_loaded) do
    @harvesters = {}
  end

  on(:tick) do
    bad_harvester!
  end

  command(:badharvester, arguments: 1..3, help: "!badharvester team [[credits_per_player=300] [interval_seconds=60]] - !badharvester allies 300 60 - Periodly gives a team some credits if their harvester is malfunctioning.", groups: [:admin, :mod, :director]) do |command|
    team, credits_per_player, interval_seconds = command.arguments

    begin
      team = Integer(team)
    rescue ArgumentError
      team = Teams.id_from_name(team)
      team = team[:id] if team
    end

    unless team
      page_player("[BadHarvester] Unknown team: #{command.arguments.first}. Try again.")

      next
    end

    begin
      credits_per_player = Integer(credits_per_player)
      raise ArgumentError unless credits_per_player.positive?
    rescue ArgumentError
      page_player("[BadHarvester] Invalid credits_per_player: #{credits_per_player}. Try again.")

      next
    end

    begin
      interval_seconds = Integer(interval_seconds)
      raise ArgumentError unless interval_seconds.positive?
    rescue ArgumentError
      page_player("[BadHarvester] Invalid interval_seconds: #{interval_seconds}. Try again.")

      next
    end

    @harvesters[team] = {
      credits_per_player: credits_per_player || 300,
      interval_seconds: interval_seconds || 60,
      counter: 0
    }

    broadcast_message("[BadHarvester] #{Teams.name(team)} Harvester malfunction detected. Dispatching additional resources...")
  end

  command(:goodharvester, arguments: 0..1, help: "!goodharvester [team] - !goodharvester allies - Removes virtual harvester.", groups: [:admin, :mod, :director]) do |command|
    team = command.arguments.first

    begin
      team = Integer(team)
    rescue ArgumentError
      team = Teams.id_from_name(team)
      team = team[:id] if team
    end

    if team && @harvesters[team]
      broadcast_message("[BadHarvester] #{Teams.name(team)} Harvester restored!")
      @harvesters.delete(team)
    elsif @harvesters.keys.size.positive?
      broadcast_message("[BadHarvester] Harvesters restored!")
      @harvesters.clear
    else
      page_player("[BadHarvester] No action taken.")
    end
  end
end
