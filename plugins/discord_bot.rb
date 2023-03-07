mobius_plugin(name: "DiscordBot", version: "0.1.0") do
  def handle_player_list(event)
    event.channel.send_embed do |embed|
      embed.title = ServerConfig.server_name
      embed.colour = 0x63452c
      embed.url = "https://w3d.cyberarm.dev/battleview/view/apb/release"

      if ServerStatus.total_players.zero?
        embed.description = "No players in-game."
      else
        team_0_players = PlayerData.players_by_team(0).count
        team_1_players = PlayerData.players_by_team(1).count

        embed.add_field(name: "#{Teams.name(0)} - #{team_0_players}/#{ServerStatus.get(:max_players)} players _(#{PluginManager.blackboard(:team_0_bot_count).to_i} bots)_", value: "Players: #{PlayerData.players_by_team(0).map(&:name).join(", ")}")
        embed.add_field(name: "#{Teams.name(1)} - #{team_1_players}/#{ServerStatus.get(:max_players)} players _(#{PluginManager.blackboard(:team_1_bot_count).to_i} bots)_", value: "Players: #{PlayerData.players_by_team(1).map(&:name).join(", ")}")
      end
    end
  end

  def handle_game_info(event)
    event.channel.send_embed do |embed|
      embed.title = ServerConfig.server_name
      embed.colour = 0x63452c
      embed.url = "https://w3d.cyberarm.dev/battleview/view/apb/release"

      team_0_players = PlayerData.players_by_team(0).count
      team_1_players = PlayerData.players_by_team(1).count

      embed.add_field(name: "Map", value: ServerStatus.get(:current_map))
      embed.add_field(name: Teams.name(0).to_s, value: "#{team_0_players}/#{ServerStatus.get(:max_players)} players _(#{PluginManager.blackboard(:team_0_bot_count).to_i} bots)_. #{ServerStatus.get(:team_0_points)} points.")
      embed.add_field(name: Teams.name(1).to_s, value: "#{team_1_players}/#{ServerStatus.get(:max_players)} players _(#{PluginManager.blackboard(:team_1_bot_count).to_i} bots)_. #{ServerStatus.get(:team_1_points)} points.")
      embed.add_field(name: "Time", value: ServerStatus.get(:time_remaining))
    end
  end

  def handle_poke(event)
    # FIXME: TODO
    event.respond "Not yet supported."

    # event.channel.send_embed do |embed|
    #   embed.title = ServerConfig.server_name
    #   embed.colour = 0x63452c
    #   embed.url = "https://w3d.cyberarm.dev/battleview/view/apb/release"

    #   embed.add_field(name: "Allies - **27/40** (0 bots) - 4520pt", value: "Players: ")
    #   embed.add_field(name: "Soviets - **0/40** (27 bots) - 452pt", value: "Players: ")
    # end
  end

  def update_status
    return unless @bot

    total_players = ServerStatus.total_players
    bot_status = total_players.zero? ? "idle" : "online"
    bot_status = "dnd" unless ServerStatus.get(:fds_responding)

    @bot.update_status(
      bot_status,
      "#{Config.discord_bot[:server_short_name].upcase}: #{ServerStatus.get(:fds_responding) ? total_players : 'OFFLINE'}",
      nil,
      0,
      false,
      Discordrb::Activity::GAME
    )
  end

  def page_server_administrators!
    return unless @bot

    Config.staff[:admin].each do |hash|
      next unless (id = hash[:discord_id])
      next unless hash[:server_owner]

      if (channel = @bot.pm_channel(id))
        if @fds_responding
          channel.send_message("**OKAY** #{Config.discord_bot[:server_short_name].upcase}: Communication with FDS restored!")
        else
          channel.send_message("**ERROR** #{Config.discord_bot[:server_short_name].upcase}: Unable to communicate with FDS!")
        end
      end
    end
  end

  def waiting_for_reply?(discord_id)
    @staff_pending_verification[discord_id]
  end

  def check_pending_staff_verifications!
    @staff_pending_verification.each do |discord_id, hash|
      if (monotonic_time - hash[:time]) >= @verification_timeout
        kick_player!(hash[:player].name, "Protected username: You failed to verify in time!")

        @staff_pending_verification.delete(discord_id)
      end
    end
  end

  on(:start) do
    @schedule_status_update = false
    @fds_responding = true
    @staff_pending_verification = {}
    @verification_timeout = 65 # seconds

    unless Config.discord_bot && Config.discord_bot[:token].length > 20
      log "Missing configuration data or invalid token"
      PluginManager.disable_plugin(self)

      next
    end

    @bot = Discordrb::Bot.new(token: Config.discord_bot[:token])

    @bot.message do |event|
      discord_id = event.message.author.id

      if (pending_staff = @staff_pending_verification[discord_id])
        message = event.message.to_s.downcase.strip

        if message == "y" || message == "yes"
          PluginManager.publish_event(:_discord_bot_verified_staff, pending_staff[:player], discord_id)
          event.message.respond("Welcome back, Commander!")
          @staff_pending_verification.delete(discord_id)
        elsif message == "n" || message == "no"
          # Kick imposter
          kick_player!(pending_staff[:player].name, "Protected username: You are an imposter!")
          @staff_pending_verification.delete(discord_id)
          event.message.respond("Roger, imposter has been kicked.")
        else
          event.message.respond("Unexpected reply, `#{event.message.to_s}`, please reply with `Yes` or `No`.")
        end

        next
      end

      if (servers = Config.discord_bot[:restrict_to_servers])
        if !servers.empty? && event.server
          next unless servers.include?(event&.server&.id)
        end
      end

      if (channels = Config.discord_bot[:restrict_to_channels])
        if !channels.empty? && event.channel
          next unless channels.include?(event&.channel&.id)
        end
      end

      next unless event.message.to_s.length.positive?
      next if false # TODO: Limit responses to a 1 per few seconds per user or something.

      case event.message.to_s.downcase.strip
      when "!pl"
        handle_player_list(event)
      when "!gi"
        handle_game_info(event)
      when "!poke"
        # handle_poke(event)
      end
    end

    @bot.run(true)

    # Let server data get fetched before updating status
    after(5) do
      @schedule_status_update = true
    end
  end

  on(:tick) do
    check_pending_staff_verifications!

    if @schedule_status_update
      @schedule_status_update = false

      update_status
    end

    if ServerStatus.get(:fds_responding) != @fds_responding
      @schedule_status_update = true
      @fds_responding = ServerStatus.get(:fds_responding)

      page_server_administrators!
    end
  end

  on(:player_joined) do
    @schedule_status_update = true
  end

  on(:map_loaded) do
    @schedule_status_update = true
  end

  on(:player_left) do
    @schedule_status_update = true
  end

  on(:shutdown) do
    @bot&.stop
  end

  on(:_discord_bot_verify_staff) do |player, discord_id|
    next unless @bot
    next if waiting_for_reply?(discord_id)

    after(5) do
      page_player(player.name, "Protected nickname, please authenticate via Discord within the next #{@verification_timeout - 5} seconds or you will be kicked.")
    end

    if (channel = @bot.pm_channel(discord_id))
      @staff_pending_verification[discord_id] = { player: player, time: monotonic_time }

      channel.send_message("Your nickname, `#{player.name}`, has joined `#{ServerConfig.server_name}`, is this you?\nReply: `Yes` or `No`.")
    end
  end
end
