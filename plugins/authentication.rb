mobius_plugin(name: "Authentication", version: "0.0.1") do
  def auto_authenticate(player)
    granted_role = nil

    Config.staff.each do |level, list|
      found = false

      list.each do |hash|
        next unless hash[:name] == player.name

        player_ip = player.address.split(";").first

        hash[:hostnames].each do |hostname|
          ip = Resolv.getaddress(hostname)

          next unless player_ip == ip

          granted_role = grant(level, player)

          found = true
          break
        end

       granted_role = grant(level, player) if hash[:force_grant]

        break if found
      end
    end

    if granted_role && Config.messages[:staff]
      case granted_role
      when :admin
        broadcast_message("[MOBIUS] #{player.name} is a Server Administrator", red: 127, green: 255, blue: 127)
      when :mod
        broadcast_message("[MOBIUS] #{player.name} is a Server Moderator", red: 127, green: 255, blue: 127)
      when :director
        broadcast_message("[MOBIUS] #{player.name} is a Game Director", red: 127, green: 255, blue: 127)
      end
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
end
