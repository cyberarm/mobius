mobius_plugin(name: "Tags", database_name: "tags", version: "0.0.1") do
  def query(name)
    if (data = database_get(name))
      data.value.split(",", 2)
    end
  end

  def insert(player, tagger, tag)
    database_set(player, "#{tagger},#{tag}")
  end

  def tag_player(player)
    tagger, tag = query(player.name.downcase)

    if tag
      log "Set #{player.name}'s TAG: #{tag}"

      RenRem.cmd("tag #{player.id} #{tag}")
    end
  end

  on(:start) do
    log "Tags online"

    after(5) do
      PlayerData.player_list.each do |player|
        tag_player(player)
      end
    end
  end

  on(:player_joined) do |player|
    tag_player(player)
  end

  command(:tag, arguments: 2, help: "!tag <nickname> <tag>", groups: [:admin, :mod]) do |command|
    tag = command.arguments.last

    if tag.length > 32
      page_player(command.issuer, "The specified tag is too long, please use 32 characters or less.")
    else
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        insert(player.name.downcase, command.issuer.name.downcase, tag)
        RenRem.cmd("tag #{player.id} #{tag}")
      else
        page_player(command.issuer, "Player #{command.arguments.first} was not found ingame, or is not unique.")
      end
    end
  end

  command(:tagself, arguments: 1, help: "!tagself <tag>") do |command|
    tag = command.arguments.first

    if tag.length > 32
      page_player(command.issuer, "The specified tag is too long, please use 32 characters or less.")
    else
      RenRem.cmd("tag #{command.issuer.id} #{tag}")
    end
  end
end
