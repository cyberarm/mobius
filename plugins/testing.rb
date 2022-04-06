Mobius::Plugin.create(name: "testing", version: "0.1.0") do
  def valid_tag_value?(value)
    true
  end

  # This event is guaranteed to be called first and only once, put initializion routines here
  on(:start) do
    log "Starting up..."
    @tags = { tags: { "username": "[O_O]"} }

    every(15) do
      log "Timer triggered"
    end

    after(180) do
      broadcast_message "180 seconds has passed since my inception!"
    end
  end

  on(:shutdown) do
    log "Good bye, cruel world!"
  end

  on(:tick) do
    log("1 second since last time!")
  end

  on(:player_join) do |player|
    if player.name.downcase.strip == "jeff"
      kick_player!(player, "No jeff's here!")
    else
      broadcast_message "#{player.name} has join the game!"

      renrem_cmd("tag, #{player.name} #{tag}") if (tag = perm_store(player.name))
    end
  end

  on(:player_leave) do |player|
    broadcast_message "#{player.name} has left!"
  end

  command(:auth, arguments: 2, help: "!auth <username> <password>") do |cmd|
    message_player(cmd.issuer, )
  end

  # If issued command doesn't have the correct number of arguments than this block won't be called
  # instead the commands help will be pm'd to the issuer
  # NOTE: Last argument will be treated as endless, i.e. "!report jeff team hampering" -> ["jeff", "team hampering"]
  command(:report, argmuments: 2, help: "!report <playername> <reason>") do |command|
    playername = command.arguments.first
    reason = command.argument.last

    if (player = find_player_by_name(playername))
      add_player_report(player, reason)
      notify_moderators("Player #{command.issuer.name} has reported #{playername} for: #{reason}")

      # Kicks player if a heuristic is triggered. e.g. large number of reports from both teams or has been reported n times
      # this session by trusted players
      auto_kick!(player)
    else
      message_player(command.issuer, "Could not find player: #{playname} in-game or in recent players.")
    end
  end

  command(:ban, arguments: 1..2, help: "!ban <playername> [reason]", groups: [:admin, :ingame]) do |command|
    playername = command.arguments.first
    reason = command.arguments.count == 2 ? command.arguments.last : "No reason given"

    # We're in a block so we can't use `return` instead use `next`
    next unless command.issuer.admin?

    if (player = find_player_by_name(playername))
      ban_player!(player, reason)
    end
  end

  command(:help, optional_arguments: 1, help: "!help [command]") do |command|
    # Automatically detect where issuer is sending from
    # i.e. ingame, W3D Server Moderation Tool or IRC
    if (cmd = command.arguments.first)
      message_player(command.issuer, find_command_by_name(cmd)&.help || "No help information for #{cmd}")
    else
      message_player(command.issuer, "!help does stuff")
    end
  end

  command(:tag, arguments: 1) do |command|
    if command.issuer.admin? || command.issuer.ingame?
      if valid_tag_value?(command.arguments.first)
        perm_store(command.issuer.name, command.arguments.first)

        renrem_cmd("tag #{command.issuer.name} #{command.arguments.first}")
    else
      message_player(command.issuer, "Not allowed to use !tag")
    end
  end
end