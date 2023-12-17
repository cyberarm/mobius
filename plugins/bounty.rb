mobius_plugin(name: "Bounty", database_name: "bounty", version: "0.0.1") do
  def reset
    @bounties = {}
    @pending_transactions = []

    @bounty_colors = {
      red: 255,
      green: 127,
      blue: 0
    }
  end

  def create_transaction(issuer, player, amount)
    # Use RenRem.enqueue to ensure we only issue `pinfo` once per tick
    RenRem.enqueue("pinfo")

    @pending_transactions << {
      issuer: issuer,
      player: player,
      amount: amount
    }
  end

  on(:start) do
    reset
  end

  on(:player_info_updated) do
    while(transaction = @pending_transactions.shift)
      issuer = PlayerData.player(transaction[:issuer])
      player = PlayerData.player(transaction[:player])
      amount = transaction[:amount]

      next unless issuer && player && amount

      if issuer.money >= amount
        RenRem.cmd("takecredits #{issuer.id} #{amount}")

        @bounties[player.name] ||= 0
        @bounties[player.name] += amount

        broadcast_message("[Bounty] #{issuer.name} has added $#{amount} to the bounty on #{player.name}. Total is now $#{@bounties[player.name]}!", **@bounty_colors)
      else
        page_player(command.issuer, "Insufficient funds, cannot place bounty.")
      end
    end
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

          broadcast_message("[Bounty] #{killer.name} has claimed the bounty on #{killed_obj[:name]} of $#{bounty}!", **@bounty_colors)
        end
      end
    end
  end

  command(:bounty, aliases: [:b], arguments: 0..2, help: "!bounty [<nickname>] [<amount>] - Places a bounty on <nickname> that will be paid out to their killer OR see their current bounty by not specifying amount.") do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    amount = command.arguments.last

    # Check bounty on command issuer
    if command.arguments.first.to_s.empty?
      b = @bounties[command.issuer.name]
      if b
        page_player(command.issuer, "[Bounty] You have a bounty of $#{b} on your head.")
      else
        page_player(command.issuer, "[Bounty] You currently don't have a bounty on your head.")
      end

      next
    end

    # Abort unless player is found
    unless player
      page_player(command.issuer, "Player not in game or name is not unique!")

      next
    end

    if amount.to_s.length.positive?
      begin
        amount = Integer(amount)
      rescue ArgumentError
        # Abort unless amount is a number
        page_player(command.issuer, "Invalid amount: #{command.arguments.first}")

        next
      end
    else
      # Amount was not specified, check bounty on player instead
      b = @bounties[player.name]
      if b
        broadcast_message("[Bounty] #{player.name} has a bounty of $#{b} on their head.", **@bounty_colors)
      else
        broadcast_message("[Bounty] #{player.name} currently doesn't have a bounty on them.", **@bounty_colors)
      end

      next
    end

    if amount.positive?
      if command.issuer.team != player.team && command.issuer.name != player.name
        # Everything looks good, create the transaction to be handling on next `pinfo` result
        create_transaction(command.issuer.name, player.name, amount)
      elsif command.issuer.name == player.name
        page_player(command.issuer, "You cannot put a bounty on yourself!")
      else
        page_player(command.issuer, "Can only place a bounty on your enemies!")
      end
    else
      page_player(command.issuer, "Cannot add nothing to bounty!")
    end
  end
end
