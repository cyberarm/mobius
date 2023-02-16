mobius_plugin(name: "Tags", version: "0.0.1") do
  def create_db_table
    database("create table if not exists tags (name text primary key, tagger text, tag text)")
  end

  def query(name)
    Database.execute("select tag from tags where name = ?", name.downcase)
  end

  def insert(player, tagger, tag)
    if query(player.name.downcase).count.positive?
      # Attempt to update first
      Database.execute("update tags set tagger=?, tag=? where name = ?", tagger.name.downcase, tag, player.name.downcase)
    else
      # Then fall back to inserting
      Database.execute("insert into tags (name, tagger, tag) values (?, ?, ?)", player.name.downcase, tagger.name.downcase, tag)
    end
  end

  def tag_player(player)
    result = query(player.name)

    if result.count.positive?
      tag = result.flatten.first
      log "Set #{player.name}'s TAG: #{tag}"

      RenRem.cmd("tag #{player.id} #{tag}")
    end
  end

  on(:start) do
    create_db_table

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
      page_player(command.issuer.name, "The specified tag is too long, please use 32 characters or less.")
    else
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        insert(player, command.issuer, tag)
        RenRem.cmd("tag #{player.id} #{tag}")
      else
        page_player(command.issuer.name, "Player #{command.arguments.first} was not found ingame, or is not unique.")
      end
    end
  end

  command(:tagself, arguments: 1, help: "!tagself <tag>") do |command|
    tag = command.arguments.first

    if tag.length > 32
      page_player(command.issuer.name, "The specified tag is too long, please use 32 characters or less.")
    else
      RenRem.cmd("tag #{command.issuer.id} #{tag}")
    end
  end
end
