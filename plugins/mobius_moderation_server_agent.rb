mobius_plugin(name: "MobiusModerationServerAgent", version: "0.0.1") do
  on(:start) do
    unless ModerationServerClient.running?
      log "Moderation Server Client not running, disabling plugin."

      PluginManager.disable_plugin(self)
    end
  end

  on(:chat) do |player, message|
    ModerationServerClient.post(
      JSON.dump(
        {
          type: :chat,
          team: player.team,
          player: player.name,
          message: message
        }
      )
    )
  end

  on(:team_chat) do |player, message|
    ModerationServerClient.post(
      JSON.dump(
        {
          type: :team_chat,
          team: player.team,
          player: player.name,
          message: message
        }
      )
    )
  end

  on(:player_joined) do
    ModerationServerClient.post(:full_payload)
  end

  on(:map_loaded) do
    ModerationServerClient.post(:full_payload)
  end

  on(:team_changed) do
    ModerationServerClient.post(:full_payload)
  end

  on(:player_left) do
    # Event is fired BEFORE player data is removed
    after(3) do
      ModerationServerClient.post(:full_payload)
    end
  end
end
