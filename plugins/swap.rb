mobius_plugin(name: "Swap", version: "0.0.1") do
  on(:start) do
    @requester = nil
  end

  # TODO: Expire requests
  on(:tick) do
  end

  on(:player_left) do|player|
    if player.name == @requester
      @requester = nil
      broadcast_message("[Swap] #{player.name} has left the game, swap has been cancelled.")
    end
  end

  command(:swap, arguments: 0, help: "!swap - Request to swap teams") do |command|
    # Swap in progress
    if @requester
      requester = PlayerData.player(PlayerData.id_from_name(@requester))

      if requester
        if requester.team != command.issuer.team
          # Mitigate abuse
          if requester.address.split(";").first != command.issuer.address.split(";").first
            requester_team = requester.team

            requester.change_team(command.issuer.team)
            command.issuer.team.change_team(requester_team)
            @requester = nil
          else
            page_player(command.issuer.name, "[Swap] You cannot swap teams with #{requester.name}, request a mod to do it for you!")
            notify_moderators("[Swap] #{requester.name} and #{command.issuer.name} attempted to swap, but they have the same IP.")
          end
        else
          page_player(command.issuer.name, "[Swap] You cannot swap teams with #{requester.name}, they are on the same team as you!")
        end
      else
        broadcast_message("[Swap] Unable to complete swap, one or both players not found ingame!")
        @requester = nil
      end

    # Request to swap
    else
      # TODO
    end
  end

  command(:swapcancel, arguments: 0, help: "!swapcancel - Cancel swap request") do |command|
  end
end
