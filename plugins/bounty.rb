mobius_plugin(name: "Bounty", database_name: "bounty", version: "0.0.1") do
  def reset
    @bounties = {}
  end

  on(:start) do
    reset
  end

  on(:map_loaded) do
    reset
  end

  on(:killed) do |hash|
    if (killed_obj = hash[:_killed_object]) && (killer_obj = hash[:_killer_object])
      if (bounty = @bounties[killed_obj[:name]])
        killed = PlayerData.player(PlayerData.name_to_id(killed_obj[:name]))
        killer = PlayerData.player(PlayerData.name_to_id(killer_obj[:name]))

        if (killed && killer) && killed.team != killer.team && killed.name != killer.name
          RenRem.cmd("givecredits #{killer.id} #{bounty}")
          @bounties.delete(killed_obj[:name])

          broadcast_message("[Bounty] #{killer.name} has claimed the bounty on #{killed_obj[:name]} of $#{bounty}!")
        end
      end
    end
  end

  command(:bounty, aliases: [:b], arguments: 2, help: "!bounty <nickname> <amount> - Places a bounty on <nickname> that will be paid out to their killer") do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    amount = command.arguments.last.to_i

    if player
      if amount.positive?
        if command.issuer.team != player.team && command.issuer.name != player.name
          # Update credit information
          RenRem.cmd("pinfo")

          # Wait for GameLog to parse response
          after(1) do
            if command.issuer.money >= amount
              RenRem.cmd("takecredits #{command.issuer.id} #{amount}")

              @bounties[player.name] ||= 0
              @bounties[player.name] += amount

              broadcast_message("[Bounty] #{command.issuer.name} has added $#{amount} to the bounty on #{player.name}. Total is now $#{@bounties[player.name]}!")
            else
              page_player(command.issuer.name, "Insufficient funds, cannot place bounty.")
            end
          end
        elsif command.issuer.name == player.name
          page_player(command.issuer.name, "You cannot put a bounty on yourself!")
        else
          page_player(command.issuer.name, "Can only place a bounty on your enemies!")
        end
      else
        page_player(command.issuer.name, "Cannot add nothing to bounty!")
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end
end
