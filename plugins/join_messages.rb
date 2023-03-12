mobius_plugin(name: "JoinMessages", database_name: "join_messages", version: "0.0.1") do
  on(:start) do
    @start_time = monotonic_time
  end

  on(:player_joined) do |player|
    dataset = database_get(player.name.downcase)

    if dataset
      red, green, blue, message = dataset.value.split(",", 4)
      broadcast_message("#{player.name}: #{message}", red: red, green: green, blue: blue) unless message.empty?
    end
  end

  command(:setjoin, arguments: 0..1, help: "!setjoin [<join text>] - Sets a message shown when you join the server (limit: 180 characters)") do |command|
    dataset = database_get(command.issuer.name.downcase)
    message = command.arguments.last

    if message.to_s.length > 180
      page_player(command.issuer.name, "Join message is to long, #{message.to_s.length} characters, max length is: 180 characters.")
    else
      red = 255
      green = 255
      blue = 255

      if dataset
        red, green, blue, _message = dataset.value.split(",", 4)
      end

      database_set(command.issuer.name.downcase, "#{red},#{green},#{blue},#{message}")
      page_player(command.issuer.name, "Your join message has been set.")
    end
  end

  command(:setjoincolor, arguments: 1, help: "!setjoincolor <hexadecimal color> - Sets join message color. e.g. !setjoincolor ff88ff") do |command|
    dataset = database_get(command.issuer.name.downcase)
    color = command.arguments.last

    if dataset.nil?
      page_player(command.issuer.name, "Must set join message before setting join color")
    elsif color.to_s.length != 6
      page_player(command.issuer.name, "Color must be 6 characters long")
    elsif !color.match?(/\A[A-Fa-f0-9]*\z/)
      page_player(command.issuer.name, "Invalid color.")
    else
      _red, _green, _blue, message = dataset.value.split(",", 4)
      red = color[0..1].to_i(16)
      green = color[2..3].to_i(16)
      blue = color[4..5].to_i(16)

      if red.between?(0, 255) && green.between?(0, 255) && blue.between?(0, 255)
        database_set(command.issuer.name.downcase, "#{red},#{green},#{blue},#{message}")
        message_player(command.issuer.name, "Your join message color has been set.", red: red, green: green, blue: blue)
      else
        page_player(command.issuer.name, "Invalid color.")
      end
    end
  end

  command(:viewjoin, arguments: 0, help: "!viewjoin - Shows message shown when you join the server, if set.") do |command|
    dataset = database_get(command.issuer.name.downcase)

    if (dataset && dataset.value.to_s.empty?) || dataset.nil?
      page_player(command.issuer.name, "You do not have a join message set. Set one with !setjoin <join text>.")
    else
      red, green, blue, message = dataset.value.split(",", 4)
      message_player(command.issuer.name, "#{command.issuer.name}: #{message}", red: red, green: green, blue: blue)
    end
  end
end
