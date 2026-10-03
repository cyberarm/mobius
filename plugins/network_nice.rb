mobius_plugin(name: "NetworkNice", database_name: "network_nice", version: "0.0.1") do
  on(:player_joined) do |player|
    SSGM.cmd("SetPlayerNetUpdateRate #{player.id} 75")
  end
end
