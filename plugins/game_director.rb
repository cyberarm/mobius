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
end
