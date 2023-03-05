mobius_plugin(name: "Bounty", version: "0.0.1") do
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
    pp [:killed, hash]

    if (killed_obj = hash[:_killed_object]) && (killer_obj = hash[:_killer_object])
      if (bounty = @bounties[killed_obj[:name]])
        killer = PlayerData.player(PlayerData.name_to_id(killer_obj[:name]))

        if killer
          RenRem.cmd("givecredits #{killer.id} #{bounty}")
          @bounties.delete(killed_obj[:name])
          broadcast_message("[Bounty] #{killer.name} has claimed the bounty on #{killed_obj[:name]} of $#{bounty}!")
          log "givecredits #{killer.id} #{bounty}"
        else
          broadcast_message("[Bounty] Something went wrong!")
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

              broadcast_message("[Bounty] #{command.issuer.name} has added $#{amount} to the $#{@bounties[player.name]} bounty on #{player.name}!")
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
