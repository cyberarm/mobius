mobius_plugin(name: "Authentication", version: "0.0.1") do
  def auto_authenticate(player)
    # TODO

    Config.staff.each do |level, list|
      found = false

      list.each do |hash|
        next unless hash[:name] == player.name

        player_ip = player.address.split(";").first

        hash[:hostnames].each do |hostname|
          ip = Resolv.getaddress(hostname)

          next unless player_ip == ip

          grant(level, player)

          found = true
          break
        end

        break if found
      end
    end
  end

  def grant(level, player)
    case level
    when :admin
      player.set_value(:administrator, true)
    when :mod
      player.set_value(:moderator, true)
    when :director
      player.set_value(:director, true)
    else
      log "WARNING: Unknown staff level: #{level}"
    end
  end

  on(:player_joined) do |player|
    auto_authenticate(player)
  end

  on(:player_left) do |player|
    # Announce departure of server staff
  end
end
