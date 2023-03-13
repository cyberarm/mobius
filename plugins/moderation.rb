mobius_plugin(name: "Moderation", database_name: "moderation", version: "0.0.1") do
  def player_granted_authority?(player, target)
    granter = (PlayerData.player(PlayerData.name_to_id(target.value(:given_director_power_from))) ||
               PlayerData.player(PlayerData.name_to_id(target.value(:given_moderator_power_from))))

    granter if granter == player
  end

  def untrusted_ip?(test_ip)
    @untrusted_ips&.find { |ip| ip.include?(test_ip) }
  end

  on(:start) do
    @untrusted_ips = []

    file_path = File.expand_path("./conf/untrusted_ips.dat")
    if File.exist?(file_path)
      File.read(file_path).lines.each do |line|
        line = line.strip

        next if line.empty? || line.start_with?("#")

        @untrusted_ips << IPAddr.new(line)
      end
    else
      log("Warning: Untrusted IP list is missing! (#{file_path})")
    end
  end

  on(:player_joined) do |player|
    after(1) do
      player_ip = player.address.split(";").first

      if untrusted_ip?(player_ip)
        notify_moderators("[Moderation] #{player.name} might be using a VPN!")
        notify_moderators("[Moderation] #{player.name}'s IP #{player_ip} matched #{untrusted_ip?(player_ip)}")
      end
    end
  end

  on(:player_left) do |player|
  end

  command(:ban, arguments: 2, help: "!ban <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to ban you!")
        RenRem.cmd("ppage #{command.issuer.id} you may not ban your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot ban yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been banned!")

        RenRem.cmd("ban #{player.id} #{command.arguments.last}")

        ip = player.address.split(";").first
        ban = Database::Ban.create(
          name: player.name.downcase,
          ip: ip,
          serial: "00000000000000000000000000000000",
          banner: command.issuer.name,
          reason: command.arguments.last
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:banlog],
          log: "[BAN] #{player.name} (#{ip}) was banned by #{command.issuer.name} for \"#{command.arguments.last}\". (Ban ID #{ban.id})"
        )
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:unban, arguments: 1, help: "!unban <nickname>", groups: [:admin, :mod]) do |command|
    nickname = command.arguments.first.strip
    db_ban = Database::Ban.first(name: nickname.downcase)

    if File.exist?(Config.banlist_path)
      # Finding the ban line index could probably be optimized, a LOT...
      raw_banlist = File.read(Config.banlist_path)
      ban = nil

      raw_banlist.lines.each_with_index do |text, line|
        next if text.strip.empty?

        nick, ip, serial, reason = text.strip.split("	")
        next unless nickname.downcase == nick.downcase

        ban = { line: line, nickname: nick, ip: ip, serial: serial, reason: reason }
      end

      if ban
        # Is this check really needed?
        if command.issuer.name.downcase == nickname.downcase
          page_player(command.issuer.name, "#{player.name} Cannot unban yourself!")
        else
          lines = raw_banlist.lines
          lines.delete_at(ban[:line])
          File.write(Config.banlist_path, lines.join)

          page_player(command.issuer.name, "#{nickname} has been unbanned.")
          RenRem.cmd("rehash_ban_list")
          db_ban&.destroy

          Database::Log.create(
            log_code: Mobius::LOG_CODE[:unbanlog],
            log: "[UNBAN] #{nickname} was unbanned by #{command.issuer.name}."
          )
        end
      else
        page_player(command.issuer.name, "Failed to find banned player: #{nickname}")
        db_ban&.destroy
      end
    else
      page_player(command.issuer.name, "BanList.tsv does not exist. #{db_ban ? 'Removing database ban' : ''}")
      db_ban&.destroy
    end
  end

  command(:kick, arguments: 2, help: "!kick <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to kick you!")
        RenRem.cmd("ppage #{command.issuer.id} you may not kick your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer.name, "#{player.name} Cannot kick yourself!")
      else
        page_player(command.issuer.name, "#{player.name} has been kicked!")

        RenRem.cmd("kick #{player.id} #{command.arguments.last}")

        ip = player.address.split(";").first
        kick = Database::Kick.create(
          name: player.name.downcase,
          ip: player.address.split(";").first,
          serial: "00000000000000000000000000000000",
          banner: command.issuer.name.downcase,
          reason: command.arguments.last
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:kicklog],
          log: "[KICK] #{player.name} (#{ip}) was kicked by #{command.issuer.name} for \"#{command.arguments.last}\". (Kick ID #{kick.id})"
        )
      end
    else
      page_player(command.issuer.name, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:mute, arguments: 2, help: "!mute <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to mute you!")
        RenRem.cmd("ppage #{command.issuer.id} you may not mute your benefactor!")
      elsif command.issuer.id == player.id
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

        RenRem.cmd("ppage #{command.issuer.id} You've made #{player.name} a temporary Moderator")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Moderator")

        player.set_value(:given_moderator_power_from, command.issuer.name)
        player.set_value(:moderator, true)

        broadcast_message("[MOBIUS] #{player.name} is a temporary Server Moderator", red: 127, green: 255, blue: 127) if Config.messages[:staff]
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

        RenRem.cmd("ppage #{command.issuer.id} You've made #{player.name} a temporary Director")
        RenRem.cmd("ppage #{player.id} You've been made a temporary Director")

        player.set_value(:given_director_power_from, command.issuer.name)
        player.set_value(:director, true)

        broadcast_message("[MOBIUS] #{player.name} has been made a temporary Game Director", red: 127, green: 255, blue: 127) if Config.messages[:staff]
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
      if (granter = player_granted_authority?(player, command.issuer))
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Moderator power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Moderator powers."

        player.delete_value(:given_moderator_power_from)
        player.delete_value(:moderator)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Server Moderator", red: 127, green: 255, blue: 127) if Config.messages[:staff]
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  command(:remove_tempdirector, aliases: [:rtd], arguments: 1, help: "!remove_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        RenRem.cmd("ppage #{granter.id} #{command.issuer.name} attempted to remove your Director power!")
        RenRem.cmd("ppage #{command.issuer.id} you may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Director powers."

        player.delete_value(:given_director_power_from)
        player.delete_value(:director)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Game Director", red: 127, green: 255, blue: 127) if Config.messages[:staff]
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  command(:mods, arguments: 0, help: "!mods - shows list of in game staff") do |command|
    admins    = PlayerData.player_list.select(&:administrator?)
    mods      = PlayerData.player_list.select(&:moderator?)
    directors = PlayerData.player_list.select(&:director?)

    if admins.size.positive?
      broadcast_message("Administrators:")
      broadcast_message(admins.sort_by(&:name).map(&:name).join(", "))
    end

    if mods.size.positive?
      broadcast_message("Moderators:")
      broadcast_message(mods.sort_by(&:name).map(&:name).join(", "))
    end

    if directors.size.positive?
      broadcast_message("Game Directors:")
      broadcast_message(directors.sort_by(&:name).map(&:name).join(", "))
    end

    if [admins + mods + directors].flatten.size.zero?
      broadcast_message("No staff in game.")
    end
  end

  command(:debug_player, aliases: [:dp], arguments: 1, help: "!debug_player <nickname> - Print out PlayerData for player", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      player.inspect.to_s.chars.each_slice(100) do |slice|
        page_player(command.issuer.name, slice.join)
      end
    else
      page_player(command.issuer.name, "Failed to find player or name not unique.")
    end
  end
end
