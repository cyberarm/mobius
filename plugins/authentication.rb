mobius_plugin(name: "Authentication", version: "0.0.1") do
  def auto_authenticate(player)
    # TODO
  end

  on(:player_joined) do |player|
    auto_authenticate(player)
  end

  on(:player_left) do |player|
    # Announce departure of server staff
  end
end
