mobius_plugin(name: "Moderation", database_name: "moderation", version: "0.0.1") do
  def player_granted_authority?(player, target)
    granter = (PlayerData.player(PlayerData.name_to_id(target.value(:given_director_power_from))) ||
               PlayerData.player(PlayerData.name_to_id(target.value(:given_moderator_power_from))))

    granter if granter == player
  end

  def untrusted_ip?(test_ip)
    @untrusted_ips&.find { |ip, line| ip.include?(test_ip) }
  end

  on(:start) do
    @untrusted_ips = []

    file_path = File.expand_path("./conf/untrusted_ips.dat")
    if File.exist?(file_path)
      File.read(file_path).lines.each do |line|
        line = line.strip

        next if line.empty? || line.start_with?("#")

        @untrusted_ips << [IPAddr.new(line), line]
      end
    else
      log("Warning: Untrusted IP list is missing! (#{file_path})")
    end
  end

  on(:player_joined) do |player|
    after(1) do
      player_ip = player.address.split(";").first

      if (ip = untrusted_ip?(player_ip))
        notify_moderators("[Moderation] #{player.name} might be using a VPN!")
        notify_moderators("[Moderation] #{player.name}'s IP #{player_ip} matched #{ip[0]} (#{ip[1]})")

        log("#{player.name}'s IP #{player_ip} matched #{ip[0]} (#{ip[1]})")
      end
    end
  end

  on(:player_left) do |player|
  end

  command(:ban, arguments: 2, help: "!ban <nickname> <reason>", groups: [:admin, :mod]) do |command|
    if command.issuer.value(:given_moderator_power_from)
      page_player(command.issuer, "Temporarily moderators may not ban players.")

      next
    end

    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to ban you!")
        page_player(command.issuer, "#{command.issuer.id} you may not ban your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot ban yourself!")
      else
        page_player(command.issuer, "#{player.name} has been banned!")

        RenRem.cmd("ban #{player.id} #{command.arguments.last}")

        ip = player.address.split(";").first
        ban = Database::ModeratorAction.create(
          name: player.name.downcase,
          ip: ip,
          serial: "00000000000000000000000000000000",
          moderator: command.issuer.name.downcase,
          reason: command.arguments.last,
          action: Mobius::MODERATOR_ACTION[:ban]
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:banlog],
          log: "[BAN] #{player.name} (#{ip}) was banned by #{command.issuer.name} for \"#{command.arguments.last}\". (ID #{ban.id})"
        )
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:unban, arguments: 1, help: "!unban <nickname>", groups: [:admin, :mod]) do |command|
    if command.issuer.value(:given_moderator_power_from)
      page_player(command.issuer, "Temporarily moderators may not unban players.")

      next
    end

    nickname = command.arguments.first.strip
    db_ban = Database::ModeratorAction.first(name: nickname.downcase, action: Mobius::MODERATOR_ACTION[:ban])

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
          page_player(command.issuer, "#{player.name} Cannot unban yourself!")
        else
          lines = raw_banlist.lines
          lines.delete_at(ban[:line])
          File.write(Config.banlist_path, lines.join)

          page_player(command.issuer, "#{nickname} has been unbanned.")
          RenRem.cmd("rehash_ban_list")
          db_ban&.destroy

          Database::Log.create(
            log_code: Mobius::LOG_CODE[:unbanlog],
            log: "[UNBAN] #{nickname} was unbanned by #{command.issuer.name}."
          )
        end
      else
        page_player(command.issuer, "Failed to find banned player: #{nickname}")
        db_ban&.destroy
      end
    else
      page_player(command.issuer, "BanList.tsv does not exist. #{db_ban ? 'Removing database ban' : ''}")
      db_ban&.destroy
    end
  end

  command(:kick, arguments: 2, help: "!kick <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to kick you!")
        page_player(command.issuer, "you may not kick your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot kick yourself!")
      else
        page_player(command.issuer, "#{player.name} has been kicked!")

        RenRem.cmd("kick #{player.id} #{command.arguments.last}")

        ip = player.address.split(";").first
        kick = Database::ModeratorAction.create(
          name: player.name.downcase,
          ip: player.address.split(";").first,
          serial: "00000000000000000000000000000000",
          moderator: command.issuer.name.downcase,
          reason: command.arguments.last,
          action: Mobius::MODERATOR_ACTION[:kick]
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:kicklog],
          log: "[KICK] #{player.name} (#{ip}) was kicked by #{command.issuer.name} for \"#{command.arguments.last}\". (ID #{kick.id})"
        )
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  # TODO: Make this command check to see if player has received n (~3) warnings in the last 24/32 hours and auto kick/temp ban them
  command(:warn, arguments: 2, help: "!warn <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to give you a warning!")
        page_player(command.issuer, "You may not issue a warning against your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot issue a warning against yourself!")
      else
        reason = command.arguments.last
        page_player(player, "[Moderation] You've been issued a warning for: #{reason}")
        page_player(command.issuer, "#{player.name} has been warned!")

        ip = player.address.split(";").first
        warning = Database::ModeratorAction.create(
          name: player.name.downcase,
          ip: player.address.split(";").first,
          serial: "00000000000000000000000000000000",
          moderator: command.issuer.name.downcase,
          reason: reason,
          action: Mobius::MODERATOR_ACTION[:warning]
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:warnlog],
          log: "[WARN] #{player.name} (#{ip}) was warned by #{command.issuer.name} for \"#{reason}\". (ID #{warning.id})"
        )
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:mute, arguments: 2, help: "!mute <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to mute you!")
        page_player(command.issuer, "You may not mute your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot mute yourself!")
      else
        page_player(command.issuer, "#{player.name} has been muted!")

        RenRem.cmd("mute #{player.id} #{command.arguments.last}")

        ip = player.address.split(";").first
        mute = Database::ModeratorAction.create(
          name: player.name.downcase,
          ip: ip,
          serial: "00000000000000000000000000000000",
          moderator: command.issuer.name.downcase,
          reason: command.arguments.last,
          action: Mobius::MODERATOR_ACTION[:mute]
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:mutelog],
          log: "[MUTE] #{player.name} (#{ip}) was muted by #{command.issuer.name} for \"#{command.arguments.last}\". (ID #{mute.id})"
        )
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:unmute, arguments: 1, help: "!unmute <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot unmute yourself!")
      else
        page_player(command.issuer, "#{player.name} has been unmute!")

        RenRem.cmd("unmute #{player.id} #{command.arguments.last}")
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:kill, arguments: 2, help: "!kill <nickname> <reason>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to kill you!")
        page_player(command.issuer, "You may not kill your benefactor!")
      elsif command.issuer.id == player.id
        page_player(command.issuer, "#{player.name} Cannot kill yourself!")
      else
        page_player(command.issuer, "#{player.name} has been kill!")

        RenRem.cmd("kill #{player.id}")

        ip = player.address.split(";").first
        kill = Database::ModeratorAction.create(
          name: player.name.downcase,
          ip: ip,
          serial: "00000000000000000000000000000000",
          moderator: command.issuer.name.downcase,
          reason: command.arguments.last,
          action: Mobius::MODERATOR_ACTION[:kill]
        )

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:killlog],
          log: "[KILL] #{player.name} (#{ip}) was killed by #{command.issuer.name} for \"#{command.arguments.last}\". (ID #{kill.id})"
        )
      end
    else
      page_player(command.issuer, "Failed to find player in game named: #{command.arguments.first}")
    end
  end

  command(:add_tempmod, aliases: [:atm], arguments: 1, help: "!add_tempmod <nickname>", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    log "Found player: #{player.name} (from: #{command.arguments.first})"

    if player
      if command.issuer != player
        log "Granting #{player.name} Moderator powers, temporarily."

        page_player(command.issuer, "You've made #{player.name} a temporary Server Moderator")
        page_player(player, "You've been made a temporary Server Moderator")

        player.set_value(:given_moderator_power_from, command.issuer.name)
        player.set_value(:moderator, true)

        broadcast_message("[MOBIUS] #{player.name} is a temporary Server Moderator", red: 127, green: 255, blue: 127) if Config.messages[:staff]

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:stafflog],
          log: "[STAFF] #{player.name} was made a temporarily Server Moderator by #{command.issuer.name}."
        )
      else
        page_player(player, "You can't add yourself, you already are a Moderator!")
      end
    else
      page_player(command.issuer, "Player not in game or name is not unique!")
    end
  end

  command(:add_tempdirector, aliases: [:atd], arguments: 1, help: "!add_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if command.issuer != player
        log "Granting #{player.name} Director powers, temporarily."

        page_player(command.issuer, "You've made #{player.name} a temporary Game Director")
        page_player(player, "You've been made a temporary Game Director")

        player.set_value(:given_director_power_from, command.issuer.name)
        player.set_value(:director, true)

        broadcast_message("[MOBIUS] #{player.name} has been made a temporary Game Director", red: 127, green: 255, blue: 127) if Config.messages[:staff]

        Database::Log.create(
          log_code: Mobius::LOG_CODE[:stafflog],
          log: "[STAFF] #{player.name} was made a temporary Game Director by #{command.issuer.name}."
        )
      else
        page_player(player, "You can't add yourself, you already are a Director!")

      end
    else
      page_player(command.issuer, "Player not in game or name is not unique!")
    end
  end

  command(:remove_tempmod, aliases: [:rtm], arguments: 1, help: "!remove_tempmod <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to remove your Moderator power!")
        page_player(command.issuer, "You may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Moderator powers."

        player.delete_value(:given_moderator_power_from)
        player.delete_value(:moderator)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Server Moderator", red: 127, green: 255, blue: 127) if Config.messages[:staff]
      end
    else
      page_player(command.issuer, "Player not in game or name is not unique!")
    end
  end

  command(:remove_tempdirector, aliases: [:rtd], arguments: 1, help: "!remove_tempdirector <nickname>", groups: [:admin, :mod, :director]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      if (granter = player_granted_authority?(player, command.issuer))
        page_player(granter, "#{command.issuer.name} attempted to remove your Director power!")
        page_player(command.issuer, "You may not remove power from your benefactor!")
      else
        log "Removing #{player.name} Director powers."

        player.delete_value(:given_director_power_from)
        player.delete_value(:director)

        broadcast_message("[MOBIUS] #{player.name} is no longer a temporary Game Director", red: 127, green: 255, blue: 127) if Config.messages[:staff]
      end
    else
      page_player(command.issuer, "Player not in game or name is not unique!")
    end
  end

  command(:mods, aliases: [:staff, :m], arguments: 0, help: "!mods - shows list of in game staff") do |command|
    admins    = PlayerData.player_list.select(&:administrator?)
    mods      = PlayerData.player_list.select(&:moderator?)
    directors = PlayerData.player_list.select(&:director?)

    if admins.size.positive?
      broadcast_message("Administrators:", red: 127, green: 255, blue: 127)
      broadcast_message("    #{admins.sort_by(&:name).map(&:name).join(", ")}", red: 127, green: 255, blue: 127)
    end

    if mods.size.positive?
      broadcast_message("Moderators:", red: 127, green: 255, blue: 127)
      broadcast_message("    #{mods.sort_by(&:name).map(&:name).join(", ")}", red: 127, green: 255, blue: 127)
    end

    if directors.size.positive?
      broadcast_message("Game Directors:", red: 127, green: 255, blue: 127)
      broadcast_message("    #{directors.sort_by(&:name).map(&:name).join(", ")}", red: 127, green: 255, blue: 127)
    end

    if [admins + mods + directors].flatten.size.zero?
      broadcast_message("No staff in game.")
    end
  end

  command(:debug_player, aliases: [:dp], arguments: 1, help: "!debug_player <nickname> - Print out PlayerData for player", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player
      player.inspect.to_s.chars.each_slice(100) do |slice|
        page_player(command.issuer, slice.join)
      end
    else
      page_player(command.issuer, "Failed to find player or name not unique.")
    end
  end

  command(:audit, aliases: [:a], arguments: 1, help: "!audit <nickname> - Print out all data for matching nickname(s) and associated ip(s)", groups: [:admin, :mod]) do |command|
    name_search = Database::IP.where(Sequel.ilike(:name, "#{command.arguments.first}%")).all

    if name_search.count.positive?
      ip_search = Database::IP.select.where(ip: name_search.map(&:ip).uniq).all

      usernames = ip_search.map(&:name).uniq
      all_usernames_match = usernames.size == 1

      page_player(command.issuer, "[Moderation: Audit] Found #{usernames.size} matching username(s) in database...")
      page_player(command.issuer, "[Moderation: Audit] #{usernames.join(', ')}") unless all_usernames_match

      # List all usernames, their ips, and moderator actions
      usernames.each do |username|
        moderator_actions = Database::ModeratorAction.select.where(name: username).all
        ips = ip_search.select { |ip| ip.name.downcase == username.downcase }

        page_player(command.issuer, "[Moderation: Audit] #{username}")
        page_player(command.issuer, "[Moderation: Audit]     IP(s)")
        ips.each_slice(3) do |ips|
          # checking for untrusted ips takes too long... cache/save to database?
          # chunk = ips.map { |ip| "#{ip.ip}#{untrusted_ip?(ip.ip) ? '[*]' : ''}" }.join(', ')
          page_player(command.issuer, "[Moderation: Audit]         #{ips.map(&:ip).join(', ')}")
        end

        if moderator_actions.size.positive?
          page_player(command.issuer, "[Moderation: Audit]     Moderator Action(s)")
          moderator_actions.each do |action|
            type = action.action
            MODERATOR_ACTION.each do |key, value|
              if value == action.action
                type = key.to_s
                break
              end
            end

            page_player(command.issuer, "[Moderation: Audit]         [#{action.created_at.strftime('%Y-%m-%d')}] [#{type.to_s.upcase}] (mod: #{action.moderator}) #{action.reason}")
          end
        end
      end
    else
      page_player(command.issuer, "Failed to name \"#{command.arguments.first}\" in database.")
    end
  end
end
