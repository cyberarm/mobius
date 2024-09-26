mobius_plugin(name: "RetiredNicknames", database_name: "retired_nicknames", version: "0.0.1") do
  on(:player_joined) do |player|
    if (config[:retired_nicknames] || []).find { |nickname| player.name.downcase.strip == nickname.downcase.strip }
      kick_player!(player, "This nickname has been retired, please choose another nickname.")
      broadcast_message("[MOBIUS] Player using #{player.name}'s nickname has been kicked. Nickname has been retired.", red: 179, green: 25, blue: 66)
    end
  end
end
