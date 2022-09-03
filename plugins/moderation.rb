mobius_plugin(name: "Moderation", version: "0.0.1") do
  def announce_rules(player)
    RenRem.cmd("cmsg 255,127,0 [MOBIUS] All players are expected to follow W3D Hub's server rules")
    RenRem.cmd("cmsg 255,127,0 [MOBIUS] This is not an official W3D Hub server")
  end

  on(:player_joined) do |player|
    announce_rules(player)

    # ban_player!(player)
    # RenRem.cmd("kick #{player.id} TESTING")
  end

  on(:player_left) do |player|
  end

  command(:ban, arguments: 2, help: "!ban <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player_id = PlayerData.name_to_id(command.arguments.first)

    if player_id.negative?
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Failed to find player in game named: #{command.arguments.first}")
    elsif command.issuer.id == player_id
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Cannot ban yourself!")
    else
      RenRem.cmd("ban #{player_id} #{command.arguments.last}")
    end
  end

  command(:unban, arguments: 1, help: "!unban <nickname>", groups: [:admin, :mod]) do |command|
    player_id = PlayerData.name_to_id(command.arguments.first)

    if player_id.negative?
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Failed to find player in game named: #{command.arguments.first}")
    elsif command.issuer.id == player_id
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Cannot unban yourself!")
    else
      # FIXME: Update banList.tsv before calling rehash
      RenRem.cmd("rehash_ban_list")
    end
  end

  command(:kick, arguments: 2, help: "!kick <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player_id = PlayerData.name_to_id(command.arguments.first)

    if player_id.negative?
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Failed to find player in game named: #{command.arguments.first}")
    elsif command.issuer.id == player_id
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Cannot ban yourself!")
    else
      RenRem.cmd("kick #{player_id} #{command.arguments.last}")
    end
  end

  command(:mute, arguments: 2, help: "!mute <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player_id = PlayerData.name_to_id(command.arguments.first)

    if player_id.negative?
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Failed to find player in game named: #{command.arguments.first}")
    elsif command.issuer.id == player_id
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Cannot mute yourself!")
    else
      # TODO: message player that they've been muted?  reason: #{command.arguments.last}
      RenRem.cmd("mute #{player_id}")
    end
  end

  command(:unmute, arguments: 1, help: "!unmute <nickname>", groups: [:admin, :mod]) do |command|
    player_id = PlayerData.name_to_id(command.arguments.first)

    if player_id.negative?
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Failed to find player in game named: #{command.arguments.first}")
    elsif command.issuer.id == player_id
      RenRem.cmd("cmsgp #{command.issuer.id} 255,127,0 Cannot unmute yourself!")
    else
      # TODO: message player that they've been unmuted?  reason: #{command.arguments.last}
      RenRem.cmd("unmute #{player_id}")
    end
  end

  command(:add_tempmod, arguments: 1, help: "!add_tempmod <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    log "Found player: #{player&.name} (from: #{command.arguments.first})"

    if player
      if command.issuer != player
        log "Granting #{player.name} Moderator powers, temporarily."

        RenRem.cmd("ppage #{player.id} You've made #{player.name} a temporary Moderator")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Moderator")

        player.set_value(:given_moderator_power_from, command.issuer.name)
        player.set_value(:moderator, true)
      else
        RenRem.cmd("ppage #{player.id} You can't add yourself, you already are a Moderator!")
      end
    end
  end

  command(:add_tempdirector, arguments: 1, help: "!add_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer != player
        log "Granting #{player.name} Director powers, temporarily."

        RenRem.cmd("ppage #{player.id} You've made #{player.name} a temporary Director")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Director")

        player.set_value(:given_director_power_from, command.issuer.name)
        player.set_value(:director, true)
      else
        RenRem.cmd("ppage #{player.id} You can't add yourself, you already are a Director!")
      end
    end
  end

  command(:remove_tempmod, arguments: 1, help: "!remove_tempmod <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      granter = PlayerData.player(PlayerData.name_to_id(player.value(:given_moderator_power_from)))

      if granter == player
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Moderator power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        log "Rmoving #{player.name} Moderator powers."

        player.delete_value(:given_moderator_power_from)
        player.delete_value(:moderator)
      end
    end
  end

  command(:remove_tempdirector, arguments: 1, help: "!remove_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      granter = PlayerData.player(PlayerData.name_to_id(player.value(:given_director_power_from)))

      if granter == player
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Director power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        player.delete_value(:given_director_power_from)
        player.delete_value(:director)
      end
    end
  end
end
