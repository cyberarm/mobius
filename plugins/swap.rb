mobius_plugin(name: "Swap", version: "0.0.1") do
  def reset
    @requester = nil
    @request_time = nil
    @delivered_half_time = false
  end

  on(:start) do
    reset
  end

  on(:tick) do
    next unless @request_time

    time_period = monotonic_time - @request_time
    if time_period >= 30.0 && !@delivered_half_time
      broadcast_message("[Swap] #{@requester} would like to swap teams, type !swap to swap with them. 30 seconds remaining.")
      @delivered_half_time = true
    elsif time_period >= 60.0
      broadcast_message("[Swap] 60 seconds are up, swap request has timed out.")

      reset
    end
  end

  on(:player_left) do |player|
    if player.name == @requester
      reset

      broadcast_message("[Swap] #{player.name} has left the game, swap has been cancelled.")
    end
  end

  command(:swap, arguments: 0, help: "!swap - Request to swap teams") do |command|
    # Swap in progress
    if @requester
      requester = PlayerData.player(PlayerData.name_to_id(@requester))

      if requester
        if requester.team != command.issuer.team
          # Mitigate abuse
          if requester.address.split(";").first != command.issuer.address.split(";").first
            requester_team = requester.team

            requester.change_team(command.issuer.team)
            command.issuer.team.change_team(requester_team)

            reset
          else
            page_player(command.issuer.name, "[Swap] You cannot swap teams with #{requester.name}, request a mod to do it for you!")
            notify_moderators("[Swap] #{requester.name} and #{command.issuer.name} attempted to swap, but they have the same IP.")
          end
        else
          page_player(command.issuer.name, "[Swap] You cannot swap teams with #{requester.name}, they are on the same team as you!")
        end
      else
        broadcast_message("[Swap] Unable to complete swap, one or both players not found ingame!")

        reset
      end

    # Request to swap
    else
      reset

      @requester = command.issuer.name
      @request_time = monotonic_time

      broadcast_message("[Swap] #{command.issuer.name} would like to swap teams, type !swap to swap with them. 60 seconds remaining.")
    end
  end

  command(:swapcancel, arguments: 0, help: "!swapcancel - Cancel swap request") do |command|
    if @requester
      requester = PlayerData.player(PlayerData.name_to_id(@requester))

      if requester
        if command.issuer.name == @requester
          reset

          broadcast_message("[Swap] #{command.issuer.name} cancelled their swap request.")
        elsif command.issuer.administrator? || command.issuer.moderator?
          reset

          broadcast_message("[Swap] Swap was cancelled by #{command.issuer.name}.")
        else
          page_player(command.issuer.name, "[Swap] You do not have permission to cancel other players swap requests.")
        end
      else
        broadcast_message("[Swap] Swap cancelled, player no longer ingame.")

        reset
      end
    else
      page_player(command.issuer.name, "[Swap] There is no swap in progress.")
    end
  end
end
