mobius_plugin(name: "Authentication", database_name: "authentication", version: "0.0.1") do
  def auto_authenticate(player)
    granted_role = nil

    Config.staff.each do |level, list|
      found = false
      data = nil

      list.each do |hash|
        next unless hash[:name].downcase == player.name.downcase
        next if player.administrator? && level == :admin
        next if player.moderator? && level == :mod
        next if player.director? && level == :director

        player_ip = player.address.split(";").first

        # Assume that if the :ip_trustable field is missing then assume that the ip is trustable, else use value
        ip_trustable = hash[:ip_trustable] == nil ? true : hash[:ip_trustable]
        if ip_trustable
          hash[:hostnames].each do |hostname|
            ip = Resolv.getaddress(hostname)

            next unless player_ip == ip

            granted_role = grant(level, player)

            found = true
            data = hash
            break
          end

          if (known_ip = Database::IP.first(name: player.name.downcase, ip: player.address.split(";").first, authenticated: true))
            if (Time.now.utc.to_i - known_ip.updated_at.to_i) >= 7 * 24 * 60 * 60 # 1 week
              # Last authentication was a week ago, IP no longer trusted

              known_ip.update(authenticated: false)
            else
              # Known and trusted IP
              granted_role = grant(level, player)
              found = true
              data = hash
            end
          end
        end

        granted_role = grant(level, player) if hash[:force_grant]

        if !granted_role && hash[:discord_id]
          PluginManager.publish_event(:_discord_bot_verify_staff, player, hash[:discord_id])

          break
        end

        break if found
      end
    end

    announce_staff(player, granted_role, hash)
  end

  def announce_staff(player, role, hash)
    # TODO: Allow silient mode for staff alt accounts
    return unless role && Config.messages[:staff]

    case role
    when :admin
      broadcast_message("[MOBIUS] #{player.name} is a Server Administrator", red: 127, green: 255, blue: 127)
    when :mod
      broadcast_message("[MOBIUS] #{player.name} is a Server Moderator", red: 127, green: 255, blue: 127)
    when :director
      broadcast_message("[MOBIUS] #{player.name} is a Game Director", red: 127, green: 255, blue: 127)
    end
  end

  def grant(level, player)
    case level
    when :admin
      player.set_value(:administrator, true)
      :admin
    when :mod
      player.set_value(:moderator, true)
      :mod
    when :director
      player.set_value(:director, true)
      :director
    else
      log "WARNING: Unknown staff level: #{level}"
      nil
    end
  end

  on(:start) do
    after(5) do
      PlayerData.player_list.each do |player|
        auto_authenticate(player)
      end
    end
  end

  on(:player_joined) do |player|
    auto_authenticate(player)
  end

  on(:player_left) do |player|
    # Announce departure of server staff
  end

  on(:_discord_bot_verified_staff) do |player, discord_id|
    Config.staff.each do |level, list|
      if (hash = list.find { |h| h[:name].downcase == player.name.downcase })
        role = grant(level, player)
        announce_staff(player, role, hash)

        # Remember player ip to auto authenticate them next time
        Database::IP.first(name: player.name.downcase, ip: player.address.split(";").first)&.update(authenticated: true)

        break
      end
    end
  end

  command(:auth, arguments: 1, help: "!auth <nickname> - Authenticates <nickname>, if their permissions level is below or the same as your own.", groups: [:admin, :mod]) do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    issuer = command.issuer

    if player == issuer
      page_player(issuer.name, "[Authentication] You cannot authenticate yourself.")

      next
    end

    found = false

    if player
      Config.staff.each do |level, list|
        if (hash = list.find { |h| h[:name].downcase == player.name.downcase })
          found = level

          if issuer.administrator? || (issuer.moderator? && [:mod, :director].include?(level))
            if (role = grant(level, player))
              announce_staff(player, role, hash)
              page_player(issuer.name, "[Authentication] Authenticated #{player.name}")
              # Rmember players IP as authenticated
              # NOTE: Disabled marking IP as trusted
              # Database::IP.first(name: player.name.downcase, ip: player.address.split(";").first)&.update(authenticated: true)

              PluginManager.publish_event(:_authenticated, player, hash)
            else
              page_player(issuer.name, "[Authentication] Unknown permission level, #{level}, failed to authenticate player.")
            end
          else
            page_player(issuer.name, "[Authentication] You do not have permission to authenticate #{player.name}")
          end

          break
        end
      end

      unless found
        page_player(issuer.name, "[Authentication] Failed to authenticate player, no permission level configured.")
      end
    else
      page_player(issuer.name, "[Authentication] Player not found on name not unique.")
    end
  end
end
