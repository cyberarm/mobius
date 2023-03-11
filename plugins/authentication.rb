mobius_plugin(name: "Authentication", database_name: "authentication", version: "0.0.1") do
  def auto_authenticate(player)
    granted_role = nil

    Config.staff.each do |level, list|
      found = false

      list.each do |hash|
        next unless hash[:name].downcase == player.name.downcase
        next if player.administrator? && level == :admin
        next if player.moderator? && level == :mod
        next if player.director? && level == :director

        player_ip = player.address.split(";").first

        hash[:hostnames].each do |hostname|
          ip = Resolv.getaddress(hostname)

          next unless player_ip == ip

          granted_role = grant(level, player)

          found = true
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

    announce_staff(player, granted_role)
  end

  def announce_staff(player, role)
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
        announce_staff(player, role)

        # Remember player ip to auto authenticate them next time
        if (known_ip = Database::IP.first(name: player.name.downcase, ip: player.address.split(";").first))
          known_ip.update(authenticated: true)
        end

        break
      end
    end
  end
end
