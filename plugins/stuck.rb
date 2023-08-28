mobius_plugin(name: "Stuck", database_name: "stuck", version: "0.0.1") do
  def abort_queued_deaths(player, reason)
    death = @queued_deaths.find do |name, time|
      name == player.name
    end

    return false unless death

    @queued_deaths.delete(player.name)

    case reason
    when :created
      page_player(player.name, "You've changed characters, respawn aborted.")
    when :damaged
      page_player(player.name, "You've taken damage, respawn aborted.")
    when :killed
      page_player(player.name, "You've died, respawn aborted.")
    when :cancelled
      page_player(player.name, "Respawn aborted.")
    end

    true
  end

  on(:start) do
    @killme_timeout = -1.0 # seconds or -1 to disable delay
    @damage_timeout = 10.0 # seconds must elipse since last damaged for !killme to be allowed
    @damaged_players = {}
    @queued_deaths = {}
  end

  on(:map_loaded) do
    @damaged_players = {}
    @queued_deaths = {}
  end

  # Abort !killme if player has respawned since requesting it
  # and remove from damaged players
  on(:created) do |object|
    next unless object[:type].downcase == "soldier"

    player = PlayerData.player(PlayerData.name_to_id(object[:name].to_s.downcase))
    next unless player

    @damaged_players.delete(player.name)
    abort_queued_deaths(player, :created)
  end

  on(:damaged) do |object|
    player = object[:_damaged_player_object]
    next unless player
    next if object[:damage].negative? || object[:damage].zero? # Healed or no actual damage

    @damaged_players[player.name] = monotonic_time
    abort_queued_deaths(player, :damaged)
  end

  # Abort !killme if player has respawned since requesting it
  # and remove from damaged players
  on(:killed) do |object|
    player = PlayerData.player(PlayerData.name_to_id(object[:killed_name].to_s.downcase))
    next unless player

    @damaged_players.delete(player.name)
    abort_queued_deaths(player, :killed)
  end

  on(:tick) do
    # cache time
    _monotonic_time = monotonic_time

    @queued_deaths.each do |name, time|
      if _monotonic_time - time >= @killme_timeout
        player = PlayerData.player(PlayerData.name_to_id(name))
        damaged_time = @damaged_players[player.name] || 100_000.0

        if (_monotonic_time - damaged_time).abs >= @damage_timeout
          RenRem.cmd("kill #{player.id}")

          broadcast_message("#{player.name} has respawned")
        else
          page_player(player.name, "You've taken damage in the last #{@damage_timeout} seconds, respawn aborted.")
        end
      end
    end

    @queued_deaths.delete_if { |name, time| _monotonic_time - time > @killme_timeout}
  end

  command(:stuck, arguments: 0, help: "Become unstuck, maybe.") do |command|
    broadcast_message("!stuck not available. Use !killme if needed. If you're in a vehicle, have someone bump you.")
  end

  # TODO: Grant refund of vehicle/character based on certain conditions
  command(:killme, arguments: 0, help: "Kill yourself") do |command|
    # default to massive number if hash lookup fails
    damaged = @damaged_players[command.issuer.name] || 100_000.0

    if (monotonic_time - damaged).abs >= @damage_timeout
      if @killme_timeout >= 0
        page_player(command.issuer.name, "You will respawn in #{@killme_timeout} seconds. Use !kc or !killcancel to abort.")

        @queued_deaths[command.issuer.name] = monotonic_time
      else
        RenRem.cmd("kill #{command.issuer.id}")

        broadcast_message("#{command.issuer.name} has respawned")
      end
    else
      page_player(command.issuer.name, "You've taken damage in the last #{@damage_timeout} seconds, cannot yet respawn.")
    end
  end

  command(:killcancel, aliases: [:kc], arguments: 0, help: "Cancel !killme") do |command|
    page_player(command.issuer.name, "No respawn queued.") unless abort_queued_deaths(command.issuer, :cancelled)
  end
end
