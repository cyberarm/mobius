mobius_plugin(name: "GameDirector", version: "0.0.1") do
  # TODO: Store map index and name to restore later if needed
  on(:start) do
  end

  # TODO: Restore original map rotation
  on(:map_loaded) do
  end

  command(:gameover, arguments: 1, help: "!gameover NOW", groups: [:admin, :mod, :director]) do |command|
    if command.arguments.first == "NOW"
      RenRem.cmd("gameover")
    else
      RenRem.cmd("ppage #{command.issuer.id} Use !gameover NOW to truely end the game")
    end
  end

  command(:setnextmap, arguments: 1, help: "!setnextmap RA_Guard", groups: [:admin, :mod, :director]) do |command|
    message_player(command.issuer.name, "Not yet implemented!")
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
end
