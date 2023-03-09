mobius_plugin(name: "Tournament", version: "0.0.1") do
  def change_player(player:, ghost: false, infected: false)
    return unless @tournament || @last_man_standing || @infection
    return unless @preset

    RenRem.cmd("eject #{player.id}")
    if ghost
      RenRem.cmd("ChangeChar #{player.id} #{player.team.zero? ? @team_0_ghost_preset : @team_1_ghost_preset}")
    elsif infected
      RenRem.cmd("ChangeChar #{player.id} #{@infected_preset}")
    else
      RenRem.cmd("ChangeChar #{player.id} #{@preset}")
    end
  end

  def change_players(ghost: false, infected: false)
    return unless tournament_active?
    return unless @preset

    PlayerData.player_list.each do |player|
      change_player(player: player, ghost: ghost, infected: infected)
    end
  end

  def just_killed?(player)
    @recent_kills.find { GameLog.current_players[player.name.downcase] }
  end

  def tournament_active?
    @tournament || @last_man_standing || @infection
  end

  def play_sound(sound)
    string = @sounds[sound]

    log "Sound missing: #{sound.inspect}" unless string
    return unless string

    log "Sound: #{sound.inspect}"
    RenRem.cmd("snda #{string}")
  end

  def play_team_sound(team_id, sound)
    string = @sounds[sound]

    log "Sound missing: #{sound.inspect}" unless string
    return unless string

    log "Sound: #{sound.inspect}"
    PlayerData.players_by_team(team_id).each do |ply|
      RenRem.cmd("sndt #{team_id} #{string}")
    end
  end

  def play_player_sound(player_id, sound)
    string = @sounds[sound]

    log "Sound missing: #{sound.inspect}" unless string
    return unless string

    log "Sound: #{sound.inspect}"
    RenRem.cmd("sndp #{player_id} #{string}")
  end

  def reset
    @tournament = false
    @last_man_standing = false
    @infection = false
    @preset = nil

    @team_0_ghost_preset = Config.tournament[:team_0_ghost_preset]
    @team_1_ghost_preset = Config.tournament[:team_1_ghost_preset]

    @infected_preset = Config.tournament[:infected_preset]

    raise "team_0_ghost_preset is not set in config!" unless @team_0_ghost_preset
    raise "team_1_ghost_preset is not set in config!" unless @team_1_ghost_preset
    raise "infected_preset is not set in config!" unless @infected_preset

    @recent_kills = []
    @tournament_kills = { team_0: 0, team_1: 0 }
    @tournament_max_kills = 1 # 25
    @ghost_players = []
    @infected_players = []

    @infected_team = 0
    @survivor_team = 1

    @round_duration = 7 * 60.0 # 7 minutes
    @round_last_minute = -1
    @round_start_time = 0
    @round_30_second_warning = false
    @round_10_second_warning = false

    @building_damage_warnings = {}
    @building_damage_freeze_duration = 5.0 # seconds

    @message_color = { red: 255, green: 200, blue: 64 } # Darkened Yellow

    missing = "buildingcomplete.wav"
    @sounds = {
      # SHARED
      team_0_victory: "eva_victorysoviet.mp3", # PLACEHOLDER
      team_1_victory: "eva_victoryallied.mp3", # PLACEHOLDER
      round_draw: missing,

      # INFECTION
      infection: "gm_infection_infection.wav",
      infected_victory: missing,
      survivor_victory: missing,
        # Survivors Only
      survivors_suvivor_lost: "levelchange.wav", # PLACEHOLDER
      survivors_survive_to_win: missing,
      survivors_last_survivor: missing,
        # Infected Only
      infected_player_infected: "gm_infection_player_infected.wav",
      infected_infected: missing,
      infected_infect_to_win: missing,
      infected_one_survivor_left: missing,
      infected_two_survivors_left: missing,
      infected_three_survivors_left: missing,

      # LAST MAN STANDING
      lastmanstanding: missing,
      lastmanstanding_new_ghost: missing, # TODO, have sound, will travel.

      # TOURNAMENT
      tournament: missing
    }

    # @auto_game_mode is not reset here, only by commands
    # What a few seconds before starting next round so that #kill_players_and_remix_teams can run
    after(5) { autostart_next_round } if @auto_game_mode
  end

  def kill_players_and_remix_teams
    after(3) do
      PlayerData.player_list.each do |player|
        RenRem.cmd("kill #{player.id}")
      end

      remix_teams
    end
  end

  def reset_auto_game_mode
    @auto_game_mode = nil
    @auto_game_mode_round = -1

    reset
  end

  def autostart_next_round
    @auto_game_mode_round ||= -1 # Array index
    @auto_game_mode_round += 1

    @round_duration = @auto_game_mode_round_duration
    active_game_mode = @auto_game_mode

    presets = nil
    begin
      Config.tournament[:presets][@auto_game_mode][@auto_game_mode_round]
    rescue NoMethodError # Presets missing
    end

    case @auto_game_mode
    when :tournament
      if presets
        try_start_tournament(presets, @round_duration)
      else
        reset_auto_game_mode
      end
    when :last_man_standing
      if presets
        try_start_last_man_standing(presets, @round_duration)
      else
        reset_auto_game_mode
      end
    when :infection
      if presets
        try_start_infection(presets[0], presets[1], @round_duration)
      else
        reset_auto_game_mode
      end
    end

    if tournament_active?
      ensure_game_clock_time!
    else
      broadcast_message("[Tournament] Auto #{active_game_mode.to_s.split("_").map(&:capitalize).join(' ')} is out of presets, deactivated!", **@message_color)
    end
  end

  def ensure_game_clock_time!
    # TODO: If game time is < round time + 1min set game clock
  end

  def try_start_tournament(preset, duration)
    if preset.to_s.empty?
      reset

      broadcast_message("[Tournament] Tournament mode has been deactivated!", **@message_color)
      log("Tournament mode has been deactivated!")
    else
      @tournament = true
      @last_man_standing = false
      @infection = false
      @preset = preset
      @round_start_time = monotonic_time
      @round_duration = duration * 60 # minutes

      broadcast_message("[Tournament] Tournament mode has been activated!", **@message_color)
      log("Tournament mode has been activated!")

      PlayerData.player_list.each do |player|
        RenRem.cmd("kill #{player.id}")
      end
    end
  end

  def try_start_last_man_standing(preset, duration)
    if preset.to_s.empty?
      reset

      broadcast_message("[Tournament] Last Man Standing mode has been deactivated!", **@message_color)
      log("Last Man Standing mode has been deactivated!")
    else
      @last_man_standing = true
      @tournament = false
      @infection = false
      @preset = preset
      @round_start_time = monotonic_time
      @round_duration = duration * 60 # minutes

      broadcast_message("[Tournament] Last Man Standing mode has been activated!", **@message_color)
      log("Last Man Standing mode has been activated!")

      PlayerData.player_list.each do |player|
        RenRem.cmd("kill #{player.id}")
      end
    end
  end

  def try_start_infection(survivor_preset, infected_preset, duration)
    if survivor_preset.to_s.empty?
      reset

      broadcast_message("[Tournament] Infection mode has been deactivated!", **@message_color)
      log("Infection mode has been deactivated!")
    else
      @infection = true
      @last_man_standing = false
      @tournament = false
      @preset = survivor_preset
      @round_start_time = monotonic_time
      @round_duration = duration * 60 # minutes

      @infected_preset = infected_preset if !infected_preset.to_s.empty?

      broadcast_message("[Tournament] Infection mode has been activated!", **@message_color)
      log("Infection mode has been activated!")

      play_sound(:infection)

      infected = (ServerStatus.total_players / 4.0).ceil
      log "Infecting #{infected} players..."

      PlayerData.player_list.shuffle.shuffle.shuffle.each_with_index do |player, i|
        if i < infected
          @infected_players[player.id] = 0
          RenRem.cmd("kill #{player.id}")
          player.change_team(@infected_team)
        else
          RenRem.cmd("kill #{player.id}")
          player.change_team(@survivor_team)
          page_player(player.name, "Group up! The infected will try to hunt you all down!")
        end
      end
    end
  end

  def try_start_auto_game_mode(game_mode, duration)
    if @auto_game_mode
      @round_duration = duration

      broadcast_message("[Tournament] Auto #{@auto_game_mode.to_s.split("_").map(&:capitalize).join(' ')} deactivated!", **@message_color)
      reset_auto_game_mode
    else
      broadcast_message("[Tournament] Auto #{game_mode.to_s.split("_").map(&:capitalize).join(' ')} activated!", **@message_color)
      @auto_game_mode = game_mode
      reset # reset triggers match start for auto game mode
    end
  end

  def infection_survivor_count
    PlayerData.players_by_team(@survivor_team).count
  end

  def ghost_count
    PlayerData.player_list.select { |ply| @ghost_players[ply.id] }.count
  end

  def the_last_man_standing
    PlayerData.player_list.find { |ply| @ghost_players[ply.id].nil? }
  end

  on(:start) do
    reset
  end

  on(:map_loaded) do |map|
    reset
  end

  on(:player_joined) do |player|
    if tournament_active?
      change_player(player: player) if @tournament

      change_player(player: player) if @last_man_standing

      if @infection
        player.change_team(@survivor_team)
        change_player(player: player)
        page_player(player.name, "[Tournament] Group up! The infected will try to hunt you all down.")
      end
    end
  end

  on(:player_left) do |player|
    @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
  end

  on(:purchased) do |hash|
    if tournament_active? && hash[:type].downcase.to_sym == :vehicle
      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

      page_player(player.name, "[Tournament] A tournament game mode is active, vehicles cannot be used.") if player
    end
  end

  on(:enter_vehicle) do |hash|
    if tournament_active? && (player_obj = hash[:_player_object])
      player = PlayerData.player(PlayerData.name_to_id(player_obj[:name]))

      if player
        page_player(player.name, "[Tournament] A tournament game mode is active, vehicles cannot be used.")
        RenRem.cmd("eject #{player.id}")
      end
    end
  end

  on(:damaged) do |hash|
    if tournament_active? && hash[:type].downcase.to_sym == :building && (player = hash[:_player_object])
      damage = hash[:damage]

      if damage.positive? # Ignore healing
        @building_damage_warnings[player.name] ||= { warnings: 0, total_damage: 0, damage: 0, frozen_at: 0, frozen: false }
        warning_hash = @building_damage_warnings[player.name]

        warning_hash[:total_damage] += damage
        warning_hash[:damage] += damage

        if warning_hash[:damage] >= 15.0 && !warning_hash[:frozen]
          warning_hash[:damage] = 0 # Reset
          warning_hash[:warnings] += 1

          # DISABLED
          if false #warning_hash[:warnings] >= 3
            page_player(player.name, "[Tournament] A tournament game mode is active, DO NOT DAMAGE BUILDINGS!")
            page_player(player.name, "[Tournament] You have been warned #{warning_hash[:warnings]} times, you have been temporarily frozen!")

            warning_hash[:frozen] = true
            warning_hash[:frozen_at] = monotonic_time
            RenRem.cmd("FreezePlayer #{player.id}")
          else
            page_player(player.name, "[Tournament] A tournament game mode is active, DO NOT DAMAGE BUILDINGS!")
          end
        end
      end
    end
  end

  on(:created) do |hash|
    # Block C4
    if hash[:type].downcase.strip.to_sym == :object && tournament_active? && hash[:preset].downcase.include?("c4")
      player_obj = hash[:_player_object]
      ply = PlayerData.player(PlayerData.name_to_id(player_obj[:name])) if player_obj

      log "#{ply ? ply.name : Teams.name(hash[:team])} placed C4 (#{hash[:preset]})"

      if player_obj && ply
        page_player(ply.name, "[Tournament] A tournament game mode is active, C4 cannot be used.")
        RenRem.cmd("disarm #{ply.id}")
      else
        PlayerData.players_by_team(hash[:team]).each do |actor| # Running out of variations on player :D
          page_player(actor.name, "[Tournament] A tournament game mode is active, C4 cannot be used.")
          RenRem.cmd("disarm #{actor.id}")
        end
      end
    end

    if hash[:type].downcase.strip.to_sym == :soldier && tournament_active? && hash[:preset].downcase != @preset.downcase
      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))
      just_killed = player && just_killed?(player)

      if just_killed
        @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
      end

      if player
        if @tournament
          if just_killed
            killer = PlayerData.player(PlayerData.name_to_id(just_killed[:_killer_object][:name]))
            @tournament_kills[:"team_#{killer.team}"] += 1 if killer
          end

          change_player(player: player)
        end

        if @last_man_standing && (hash[:preset].downcase != @team_0_ghost_preset.downcase && hash[:preset].downcase != @team_1_ghost_preset.downcase)
          if just_killed
            just_ghosted = @ghost_players[player.id].nil?

            @ghost_players[player.id] = true
            change_player(player: player, ghost: true)
            player.change_team(3, kill: false)

            if just_ghosted
              broadcast_message("[Tournament] #{player.name} has become a ghost!", **@message_color)
              page_player(player.name, "You've become a ghost, go forth and haunt the living!")
              play_sound(:lastmanstanding_new_ghost)
            end
          else
            change_player(player: player) unless @ghost_players[player.id]
          end
        end

        if @infection && hash[:preset].downcase != @infected_preset.downcase
          is_infected = @infected_players[player.id]

          if just_killed || is_infected
            just_infected = @infected_players[player.id].nil? || @infected_players[player.id] == 0
            log "Player: #{player.name} just infected? #{just_infected}"

            @infected_players[player.id] = true
            player.change_team(@infected_team)
            change_player(player: player, infected: true)

            if just_infected
              if infection_survivor_count.positive?
                broadcast_message("[Tournament] #{player.name} has been infected, there are only #{infection_survivor_count} survivors left!", **@message_color)
                page_player(player.name, "You have been infected, hunt down the #{infection_survivor_count} survivors!")
              else
                broadcast_message("[Tournament] #{player.name} has been infected, there are no survivors left!", **@message_color)
              end
              log("#{player.name} has been infected!")

              # Only play sound if infection has been happening for 5 or more seconds, prevents "Infection" sound form getting overlayed
              if monotonic_time - @round_start_time >= 5.0
                play_team_sound(@infected_team, :infected_player_infected)
                play_team_sound(@survivor_team, :survivors_suvivor_lost)
              end

              if infection_survivor_count == 1
                PlayerData.players_by_team(@survivor_team).each do |ply|
                  page_player(ply.name, "You are the last survivor!")
                  play_player_sound(ply.name, :survivors_last_survivor)
                end
              end
            end
          else
            unless is_infected
              player.change_team(@survivor_team)
              change_player(player: player)
            end
          end
        end
      end
    end
  end

  on(:killed) do |hash|
    if tournament_active? && (killed_obj = hash[:_killed_object]) && (killer_obj = hash[:_killer_object])
      killed = PlayerData.player(PlayerData.name_to_id(killed_obj[:name]))
      killer = PlayerData.player(PlayerData.name_to_id(killer_obj[:name]))

      @recent_kills << hash if (killed && killer) && killed.team != killer.team && killed.name != killer.name
    end
  end

  on(:tick) do
    if tournament_active?
      if @tournament
        winning_team = -1 # -1 = draw, 0 and 1 are teams
        highest_kill_count = -1

        @tournament_kills.each do |team, kills|
          team = team.to_s.split("_").last.to_i

          if kills >= @tournament_max_kills
            highest_kill_count = kills if kills > highest_kill_count

            if winning_team >= 0
              winning_team = -1
            else
              winning_team = team
            end
          end
        end

        if highest_kill_count >= @tournament_max_kills
          if winning_team == -1
            broadcast_message("[Tournament] The Tournament is a draw!", **@message_color)
            play_sound(:round_draw)
          else
            losing_team = winning_team.zero? ? 1 : 0
            broadcast_message("[Tournament] #{Teams.name(winning_team)} have won the Tournament with #{highest_kill_count} kills to the #{Teams.name(losing_team)} #{@tournament_kills[:"team_#{losing_team}"]} kills!", **@message_color)
            play_sound(:"team_#{winning_team}_victory")
          end

          reset

          kill_players_and_remix_teams
        end

      elsif @last_man_standing
        if ghost_count == PlayerData.player_list.count - 1
          broadcast_message("[Tournament] #{the_last_man_standing.name} won as the Last Man Standing!", **@message_color)
          play_sound(:"team_#{the_last_man_standing.team}_victory")
          log("#{the_last_man_standing.name} won as the Last Man Standing!")

          reset

          kill_players_and_remix_teams

        elsif PlayerData.players_by_team(0).count.zero? || PlayerData.players_by_team(1).count.zero?
          winning_team = if PlayerData.players_by_team(0).count.zero?
                           Teams.name(1)
                         else
                           Teams.name(0)
                         end

          broadcast_message("[Tournament] The #{winning_team} have won the Last Man Standing!", **@message_color)
          play_sound(:"team_#{Teams.id_from_name(winning_team)[:id]}_victory")
          log("#{winning_team} have won the Last Man Standing!")

          reset

          kill_players_and_remix_teams
        end

      elsif @infection
        if infection_survivor_count.zero?
          broadcast_message("[Tournament] All players have been infected!", **@message_color)
          play_sound(:infected_victory)
          log("All players have been infected!")

          reset

          kill_players_and_remix_teams
        end
      end

      # Manage round timer
      if tournament_active?
        time_elapsed = monotonic_time - @round_start_time
        time_remaining = @round_duration - time_elapsed
        current_minute = (time_remaining / 60.0).ceil

        if time_elapsed >= @round_duration
          if @tournament
            winning_team = -1 # -1 = draw, 0 and 1 are teams
            highest_kill_count = -1

            @tournament_kills.each do |team, kills|
              team = team.to_s.split("_").last.to_i

              if kills >= highest_kill_count
                highest_kill_count = kills if kills > highest_kill_count

                if winning_team >= 0
                  winning_team = -1
                else
                  winning_team = team
                end
              end
            end

            if winning_team == -1
              broadcast_message("[Tournament] The Tournament is a draw!", **@message_color)
            else
              losing_team = winning_team.zero? ? 1 : 0
              broadcast_message("[Tournament] #{Teams.name(winning_team)} have won the Tournament with #{highest_kill_count} kills to the #{Teams.name(losing_team)} #{@tournament_kills[:"team_#{losing_team}"]} kills!", **@message_color)
              play_sound(:"team_#{winning_team}_victory")
            end
          elsif @last_man_standing
            broadcast_message("[Tournament] Last Man Standing is a draw!", **@message_color)
            play_sound(:round_draw)
          elsif @infection
            broadcast_message("[Tournament] The survivors have survived!", **@message_color)
            play_sound(:survivor_victory)
          end

          reset

          kill_players_and_remix_teams

        elsif current_minute != @round_last_minute
          @round_last_minute = current_minute
          minutes = current_minute > 1

          if @tournament || @last_man_standing
            broadcast_message("[Tournament] #{minutes ? "#{current_minute} minutes" : "1 minute"} remaining!", **@message_color)
          elsif @infection
            message_team(@infected_team, "[Tournament] Infected, only #{minutes ? "#{current_minute} minutes" : "1 minute"} remaining!", **@message_color)
            message_team(@survivor_team, "[Tournament] Survivors, hold out for another #{minutes ? "#{current_minute} minutes" : "minute"}!", **@message_color)
          end
        elsif time_remaining <= 30.0 && !@round_30_second_warning
          @round_30_second_warning = true

          if @tournament || @last_man_standing
            broadcast_message("[Tournament] 30 seconds remaining!", **@message_color)
          elsif @infection
            message_team(@infected_team, "[Tournament] Infected, only 30 seconds remaining!", **@message_color)
            message_team(@survivor_team, "[Tournament] Survivors, hold out for another 30 seconds!", **@message_color)
          end
        elsif time_remaining <= 10.0 && !@round_10_second_warning
          @round_10_second_warning = true

          if @tournament || @last_man_standing
            broadcast_message("[Tournament] 10 seconds remaining!", **@message_color)
          elsif @infection
            message_team(@infected_team, "[Tournament] Infected, only 10 seconds remaining!", **@message_color)
            message_team(@survivor_team, "[Tournament] Survivors, hold out for another 10 seconds!", **@message_color)
          end
        end
      end

      # manage de-icing bad actors
      @building_damage_warnings.each do |nickname, hash|
        if hash[:frozen] && monotonic_time - hash[:frozen_at] >= @building_damage_freeze_duration
          player = PlayerData.player(PlayerData.name_to_id(nickname))

          if player
            page_player(player.name, "[Tournament] You have been unfrozen!")
            RenRem.cmd("UnFreezePlayer #{player.id}")

            hash[:frozen] = false
            hash[:frozen] = false
            hash[:warnings] = 0
            hash[:damage] = 0
          end
        end
      end
    end
  end

  command(:tournament, arguments: 0..2, help: "!tournament [<soldier_preset>, [<duration in minutes>]] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_tournament(preset, duration)
  end

  command(:lastmanstanding, arguments: 0..2, help: "!lastmanstanding [<soldier_preset>, [<duration in minutes>]] - Evicts all players from vehicles and forces everyone to play as <soldier_preset>, on death they become ghosts.", groups: [:admin, :mod, :director]) do |command|
    preset = command.arguments.first
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_last_man_standing(preset, duration)
  end

  command(:infection, arguments: 0..3, help: "!infection [<survivor_preset>, [<infected_preset>], [<duration in minutes>]] - Evicts all players from vehicles and forces everyone to play as <hunter_preset> and <infected_preset>, on death they become infected.", groups: [:admin, :mod, :director]) do |command|
    survivor_preset = command.arguments.first
    infected_preset = command.arguments[1]
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_infection(survivor_preset, infected_preset, duration)
  end

  command(:infect, arguments: 1, help: "!infect <nickname> - Manually infect player.", groups: [:admin, :mod]) do |command|
    if @infection
      player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

      if player
        @infected_players[player.id] = 0
        RenRem.cmd("kill #{player.id}")
        player.change_team(@infected_team)

        log("#{player.name} has been manually infected by #{command.issuer.name}")
      else
        page_player(command.issuer.name, "Player #{command.arguments.first} was not found ingame, or is not unique.")
      end
    else
      page_player(command.issuer.name, "Infection mode is not enabled.")
    end
  end

  command(:auto_tournament, aliases: [:autot], arguments: 0..1, help: "!auto_tournament [<duration in minutes>] - Starts a Tournament game that will cycle through configured presets", groups: [:admin, :mod, :director]) do |command|
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_auto_game_mode(:tournament, duration)
  end

  command(:auto_lastmanstanding, aliases: [:autolms], arguments: 0..1, help: "!auto_lastmanstanding [<duration in minutes>] - Starts a Last Man Standing game that will cycle through configured presets", groups: [:admin, :mod, :director]) do |command|
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_auto_game_mode(:last_man_standing, duration)
  end

  command(:auto_infection, aliases: [:autoi], arguments: 0..1, help: "!auto_infection [<duration in minutes>] - Starts an Infection game that will cycle through configured presets", groups: [:admin, :mod, :director]) do |command|
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    try_start_auto_game_mode(:infection, duration)
  end
end
