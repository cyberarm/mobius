mobius_plugin(name: "MapGuard", database_name: "mapguard", version: "0.0.1") do
  def auto_set_next_map(mode)
    queue = nil
    pool = nil

    case mode
    when :bots_player_count
      queue = @bots_player_count_maps_queue
      pool = :bots_player_count_maps
    when :low_player_count
      queue = @low_player_count_maps_queue
      pool = :low_player_count_maps
    when :high_player_count
      queue = @high_player_count_maps_queue
      pool = :high_player_count_maps
    end

    if queue.size.zero?
      log "Queue is empty, resetting to full list."
      instance_variable_set(:"@#{pool}_queue", config[pool])

      remove_map_from_queues(@cached_current_map)

      queue = instance_variable_get(:"@#{pool}_queue")
    end

    mapname = queue.sample

    original_map = ServerConfig.rotation.rotate(ServerStatus.get(:current_map_number) + 1)&.first
    array_index = ServerConfig.rotation.index(original_map)

    RenRem.cmd("mlistc #{array_index} #{mapname}")

    ServerConfig.data[:nextmap_changed_id] = array_index
    ServerConfig.data[:nextmap_changed_mapname] = original_map

    # Update rotation
    log "Switching #{original_map} with #{mapname}"
    ServerConfig.rotation[array_index] = mapname

    remove_map_from_queues(mapname)
  end

  def remove_map_from_queues(mapname)
    [@bots_player_count_maps_queue, @low_player_count_maps_queue, @high_player_count_maps_queue].each do |queue|
      queue.delete_if { |m| m.downcase == mapname.downcase }
    end
  end

  def display_maps_left(player, queue)
    queue.each_slice(6) do |slice|
      message_player(player.name,
        slice.join(", ")
      )
    end
  end

  def coop_enabled?
    (PluginManager.blackboard(:team_0_bot_count).to_i + PluginManager.blackboard(:team_1_bot_count).to_i).positive?
  end

  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    @bots_player_count_maps = config[:bots_player_count_maps]
    @low_player_count_maps = config[:low_player_count_maps]
    @high_player_count_maps = config[:high_player_count_maps]

    @low_player_count = config[:low_player_count_number]
    @high_player_count = config[:high_player_count_number]

    @all_maps = [@bots_player_count_maps, @low_player_count_maps, @high_player_count_maps].flatten.uniq

    @bots_player_count_maps_queue = config[:bots_player_count_maps]
    @low_player_count_maps_queue = config[:low_player_count_maps]
    @high_player_count_maps_queue = config[:high_player_count_maps]

    after(1) do
      @cached_current_map = ServerStatus.get(:current_map)
    end
  end

  on(:map_loaded) do |mapname|
    @cached_current_map = File.basename(mapname, ".mix")
    player_count = PlayerData.player_list.select(&:ingame?).size

    if coop_enabled? && player_count < @low_player_count
      auto_set_next_map(:bots_player_count)
    elsif player_count < @high_player_count
      auto_set_next_map(:low_player_count)
    else
      auto_set_next_map(:high_player_count)
    end

    mapnum = ServerStatus.get(:current_map_number)
    after(30) do
      map = ServerConfig.rotation.rotate(ServerStatus.get(:current_map_number) + 1)&.first

      broadcast_message("[MapGuard] The next map will be: #{map}") if mapnum == ServerStatus.get(:current_map_number)
    end
  end

  command(:botmapqueue, aliases: [:bmq], arguments: 0, help: "!bmq - Displays bots playercount queue remaining maps.", groups: [:admin, :mod, :director]) do |command|
    display_maps_left(command.issuer, @bots_player_count_maps_queue)
  end

  command(:lowplayermapqueue, aliases: [:lmq], arguments: 0, help: "!lmq - Displays low playercount queue remaining maps.", groups: [:admin, :mod, :director]) do |command|
    display_maps_left(command.issuer, @low_player_count_maps_queue)
  end

  command(:highplayermapqueue, aliases: [:hmq], arguments: 0, help: "!hmq - Displays high playercount queue remaining maps.", groups: [:admin, :mod, :director]) do |command|
    display_maps_left(command.issuer, @high_player_count_maps_queue)
  end
end
