mobius_plugin(name: "Moderation", version: "0.0.1") do
  def announce_rules(player)
    RenRem.cmd("cmsg 255,127,0 [MOBIUS] All players are expected to follow W3D Hub's server rules")
    RenRem.cmd("cmsg 255,127,0 [MOBIUS] This is not an official W3D Hub server")
  end

  on(:player_joined) do |player|
    announce_rules(player)
  end

  on(:player_left) do |player|
  end

  command(:ban, arguments: 2, help: "!ban <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot ban yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been banned!")

        RenRem.cmd("ban #{player.id} #{command.arguments.last}")
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:unban, arguments: 1, help: "!unban <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot unban yourself!")
      else
        # FIXME: Update banList.tsv before calling rehash
        page_player(command.issuer.name, "Not Implemented. Contact server adminstrator.")
        RenRem.cmd("rehash_ban_list")
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:kick, arguments: 2, help: "!kick <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot kick yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been kicked!")

        RenRem.cmd("kick #{player.id} #{command.arguments.last}")
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:mute, arguments: 2, help: "!mute <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot mute yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been muted!")

        RenRem.cmd("mute #{player.id} #{command.arguments.last}")
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:unmute, arguments: 1, help: "!unmute <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot unmute yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been unmute!")

        RenRem.cmd("unmute #{player.id} #{command.arguments.last}")
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:add_tempmod, aliases: [:atm], arguments: 1, help: "!add_tempmod <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    log "Found player: #{player.name} (from: #{command.arguments.first})"

    if player
      if command.issuer != player
        log "Granting #{player.name} Moderator powers, temporarily."

        RenRem.cmd("ppage #{player.id} You've made #{player.name} a temporary Moderator")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Moderator")

        player.set_value(:given_moderator_power_from, command.issuer.name)
        player.set_value(:moderator, true)

        broadcast_message("[MOBIUS] #{player.name} is a temporary Server Moderator", red: 127, green: 255, blue: 127)
      else
        RenRem.cmd("ppage #{player.id} You can't add yourself, you already are a Moderator!")
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  command(:add_tempdirector, aliases: [:atd], arguments: 1, help: "!add_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer != player
        log "Granting #{player.name} Director powers, temporarily."

        RenRem.cmd("ppage #{player.id} You've made #{player.name} a temporary Director")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Director")

        player.set_value(:given_director_power_from, command.issuer.name)
        player.set_value(:director, true)

        broadcast_message("[MOBIUS] #{player.name} has been made a temporary Game Director", red: 127, green: 255, blue: 127)
      else
        RenRem.cmd("ppage #{player.id} You can't add yourself, you already are a Director!")
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  command(:remove_tempmod, aliases: [:rtm], arguments: 1, help: "!remove_tempmod <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      granter = PlayerData.player(PlayerData.name_to_id(player.value(:given_moderator_power_from)))

      if granter == player
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Moderator power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Moderator powers."

        player.delete_value(:given_moderator_power_from)
        player.delete_value(:moderator)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Server Moderator", red: 127, green: 255, blue: 127)
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  command(:remove_tempdirector, aliases: [:rtd], arguments: 1, help: "!remove_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      granter = PlayerData.player(PlayerData.name_to_id(player.value(:given_director_power_from)))

      if granter == player
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Director power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Director powers."

        player.delete_value(:given_director_power_from)
        player.delete_value(:director)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Game Director", red: 127, green: 255, blue: 127)
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end
end
