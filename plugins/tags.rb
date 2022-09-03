mobius_plugin(name: "Tags", version: "0.0.1") do
  def create_db_table
    database("create table if not exists tags (name text primary key, tagger text, tag text)")
  end

  def query(name)
    Database.execute("select tag from tags where lower(name) = '#{name.downcase}' limit 1")
  end

  on(:start) do
    create_db_table

    log "Tags online"
  end

  on(:player_joined) do |player|
    result = query(player.name)

    if result.count.positive?
      tag = result.flatten.first
      log "Set #{player.name}'s TAG: #{tag}"

      RenRem.cmd("tag #{player.id} #{tag}")
    else
      log "Did not find a tag for player: #{player.name}"
    end
  end

  command(:tag, arguments: 2, help: "!tag <nickname> <tag>", groups: [:admin, :mod]) do |command|
    pp command
  end

  command(:tagself, arguments: 1, help: "!tagself <tag>") do |command|
    # TODO: Save to DB, or only do that for !tag?

    RenRem.cmd("tag #{command.issuer.id} #{command.arguments.first}")
  end
end
