mobius_plugin(name: "MobiusAgent", version: "0.0.1") do
  on(:player_joined) do
    ModerationServerClient.post(:full_payload)
  end

  on(:map_loaded) do
    ModerationServerClient.post(:full_payload)
  end

  on(:player_left) do
    ModerationServerClient.post(:full_payload)
  end
end
