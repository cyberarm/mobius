mobius_plugin(name: "Tournament", version: "0.0.1") do
  def change_player(player:, ghost: false, infected: false)
    return unless @tournament || @last_man_standing || @infection
    return unless @preset

    RenRem.cmd("eject #{player.id}")
    if ghost
      team = @ghost_players[player.id] # team of player at death
      RenRem.cmd("ChangeChar #{player.id} #{team.zero? ? @team_0_ghost_preset : @team_1_ghost_preset}")
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

  def tournament_active?
    @tournament || @last_man_standing || @infection
  end

  def c4?(string)
    if string.include?("c4")
      return false if string.include?("medic")

      return true
    end
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
    RenRem.cmd("sndt #{team_id} #{string}")
  end

  def play_player_sound(player_id, sound)
    string = @sounds[sound]

    log "Sound missing: #{sound.inspect}" unless string
    return unless string

    log "Sound: #{sound.inspect}"
    RenRem.cmd("sndp #{player_id} #{string}")
  end

  def construction_yard!(player)
    RenRem.cmd("attachscript #{player.id} dp88_buildingScripts_functionRepairBuildings 50,None,false")
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

    @tournament_kills = { team_0: 0, team_1: 0 }
    @tournament_max_kills = 15
    @tournament_leading_team = -1
    @tournament_last_announced_kills_remaining = -1
    @tournament_announce_kills_remaining_at = [20, 15, 10, 5, 4, 3, 2, 1]
    @ghost_players = []
    @infected_players = []

    @infected_team = 0
    @survivor_team = 1

    @round_duration = 7 * 60.0 # 7 minutes
    @round_last_minute = -1
    @round_start_time = 0
    @round_30_second_warning = false
    @round_10_second_warning = false

    @message_color = { red: 255, green: 200, blue: 64 } # Darkened Yellow

    missing = "buildingcomplete.wav"
    @sounds = {
      # SHARED
      team_0_victory: "eva_victorysoviet.mp3", # PLACEHOLDER
      team_1_victory: "eva_victoryallied.mp3", # PLACEHOLDER
      round_draw: missing,

      # INFECTION
      infection: "gm_infection_infection.wav",
      infected_victory: "eva_victorysoviet.mp3", # PLACEHOLDER
      survivor_victory: "eva_victoryallied.mp3", # PLACEHOLDER
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
    # Wait a few seconds before starting next round so that #kill_players_and_remix_teams can run
    after(@auto_game_mode_round.positive? ? 7 : 0) { autostart_next_round } if @auto_game_mode
  end

  def kill_players_and_remix_teams
    after(3) do
      # Only kill players auto game mode is inactive or is on the first round
      if !@auto_game_mode || (@auto_game_mode && @auto_game_mode_round.zero?)
        PlayerData.player_list.each do |player|
          RenRem.cmd("kill #{player.id}")
        end
      end

      remix_teams
    end
  end

  def reset_auto_game_mode
    @auto_game_mode = nil
    @auto_game_mode_round = -1

    reset

    @auto_game_mode_round_duration = @round_duration
  end

  def autostart_next_round
    @auto_game_mode_round ||= -1 # Array index
    @auto_game_mode_round += 1

    @round_duration = @auto_game_mode_round_duration
    active_game_mode = @auto_game_mode

    presets = nil
    begin
      presets = Config.tournament[:presets][@auto_game_mode][@auto_game_mode_round]
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
      presets_list = Config.tournament[:presets][@auto_game_mode]
      broadcast_message("[Tournament] Auto #{active_game_mode.to_s.split("_").map(&:capitalize).join(' ')} has started round #{@auto_game_mode_round + 1} of #{presets_list.count}!", **@message_color)

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
      broadcast_message("[Tournament] Collectively get #{@tournament_max_kills} kills to win!", **@message_color)
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

      infected = (PlayerData.player_list.count / 4.0).ceil
      log "Infecting #{infected} players..."

      infected_players = []
      survivor_players = []

      PlayerData.player_list.shuffle.shuffle.shuffle.each_with_index do |player, i|
        if i < infected
          @infected_players[player.id] = 0
          player.change_team(@infected_team, kill: false)

          infected_players << player
        else
          player.change_team(@survivor_team, kill: false)

          survivor_players << player
        end
      end

      # Seperating out the kills so that #infection_survivor_count has a current value
      infected_players.each do |player|
        RenRem.cmd("kill #{player.id}")

        handle_infection_death(player, true)
      end

      survivor_players.each do |player|
        RenRem.cmd("kill #{player.id}")
        page_player(player.name, "Group up! The infected will try to hunt you all down!")
      end
    end
  end

  def try_start_auto_game_mode(game_mode, duration)
    if @auto_game_mode
      broadcast_message("[Tournament] Auto #{@auto_game_mode.to_s.split("_").map(&:capitalize).join(' ')} deactivated!", **@message_color)
      reset_auto_game_mode
    else
      broadcast_message("[Tournament] Auto #{game_mode.to_s.split("_").map(&:capitalize).join(' ')} activated!", **@message_color)
      @auto_game_mode = game_mode
      reset # reset triggers match start for auto game mode
    end
  end

  def handle_infection_death(player, match_start = false)
    survivor_count = infection_survivor_count
    just_infected = @infected_players[player.id].nil? || @infected_players[player.id] == 0
    log "Player: #{player.name} just infected? #{just_infected}"

    # Mark player has "already infected" so as to not spam them with messages
    @infected_players[player.id] = true

    if just_infected
      # Since we don't change the players team here we need to subtract 1 so that the count is accurate, but NOT on match/round start
      survivor_count -= 1 unless match_start

      if survivor_count.positive?
        broadcast_message("[Tournament] #{player.name} has been infected, there are only #{survivor_count} survivors left!", **@message_color)
        page_player(player.name, "You have been infected, hunt down the #{survivor_count} survivors!")
      else
        broadcast_message("[Tournament] #{player.name} has been infected, there are no survivors left!", **@message_color)
      end
      log("#{player.name} has been infected!")

      # Only play sound if infection has been happening for 5 or more seconds, prevents "Infection" sound form getting overlayed
      if monotonic_time - @round_start_time >= 5.0
        play_team_sound(@infected_team, :infected_player_infected)
        play_team_sound(@survivor_team, :survivors_suvivor_lost)
      end

      if survivor_count == 1
        PlayerData.players_by_team(@survivor_team).each do |ply|
          # Since the player is technically still on the survivor team, we need this check to avoid sending it to "both survivoring players"
          next if @infected_players[ply.id]

          page_player(ply.name, "You are the last survivor!")
          play_player_sound(ply.name, :survivors_last_survivor)
        end
      end
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
    reset_auto_game_mode
  end

  on(:map_loaded) do |map|
    reset_auto_game_mode
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

  # on(:player_left) do |player|
  #   @recent_kills.delete_if { |h| h[:killed_object] == GameLog.current_players[player.name.downcase] }
  # end

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

  # on(:damaged) do |hash|
  #   if tournament_active? && hash[:type].downcase.to_sym == :building && (player = hash[:_player_object])
  #     damage = hash[:damage]

  #     if damage.positive? # Ignore healing
  #       @building_damage_warnings[player.name] ||= { warnings: 0, total_damage: 0, damage: 0, frozen_at: 0, frozen: false }
  #       warning_hash = @building_damage_warnings[player.name]

  #       warning_hash[:total_damage] += damage
  #       warning_hash[:damage] += damage

  #       if warning_hash[:damage] >= 15.0 && !warning_hash[:frozen]
  #         warning_hash[:damage] = 0 # Reset
  #         warning_hash[:warnings] += 1

  #         # DISABLED
  #         if false #warning_hash[:warnings] >= 3
  #           page_player(player.name, "[Tournament] A tournament game mode is active, DO NOT DAMAGE BUILDINGS!")
  #           page_player(player.name, "[Tournament] You have been warned #{warning_hash[:warnings]} times, you have been temporarily frozen!")

  #           warning_hash[:frozen] = true
  #           warning_hash[:frozen_at] = monotonic_time
  #           RenRem.cmd("FreezePlayer #{player.id}")
  #         else
  #           page_player(player.name, "[Tournament] A tournament game mode is active, DO NOT DAMAGE BUILDINGS!")
  #         end
  #       end
  #     end
  #   end
  # end

  on(:created) do |hash|
    # pp [:created, hash]

    # Block C4
    if hash[:type].downcase.strip.to_sym == :object && tournament_active? && c4?(hash[:preset].downcase)
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

    if hash[:type].downcase.strip.to_sym == :soldier && tournament_active?
      preset_needs_changing = hash[:preset].downcase != @preset.downcase

      player = PlayerData.player(PlayerData.name_to_id(hash[:name]))

      if player
        if @tournament
          change_player(player: player) if preset_needs_changing
          construction_yard!(player) unless preset_needs_changing
        end

        if @last_man_standing && (hash[:preset].downcase != @team_0_ghost_preset.downcase && hash[:preset].downcase != @team_1_ghost_preset.downcase)
          is_ghost = @ghost_players[player.id]

          if is_ghost
            change_player(player: player, ghost: true)
            player.change_team(3, kill: false)
          else
            if preset_needs_changing
              change_player(player: player)
            elsif !preset_needs_changing && player.team > 1
              construction_yard!(player)
            end
          end
        end

        if @infection && hash[:preset].downcase != @infected_preset.downcase
          is_infected = @infected_players[player.id]

          if is_infected
            @infected_players[player.id] = true
            player.change_team(@infected_team)
            change_player(player: player, infected: true)
          else
            player.change_team(@survivor_team)
            change_player(player: player) if preset_needs_changing
            construction_yard!(player) unless preset_needs_changing
          end
        elsif @infection && hash[:preset].downcase == @infected_preset.downcase
          construction_yard!(player)
        end
      end
    end
  end

  on(:killed) do |hash|
    # pp [:killed, hash]

    if tournament_active? && (killed_obj = hash[:_killed_object]) && (killer_obj = hash[:_killer_object])
      killed = PlayerData.player(PlayerData.name_to_id(killed_obj[:name]))
      killer = PlayerData.player(PlayerData.name_to_id(killer_obj[:name]))

      if (killed && killer) && killed.team != killer.team && killed.name != killer.name
        if @tournament
          @tournament_kills[:"team_#{killer.team}"] += 1

          team_0_kills = @tournament_kills[:team_0]
          team_1_kills = @tournament_kills[:team_1]
          winning_team = team_0_kills > team_1_kills ? 0 : 1
          winning_team = -1 if team_0_kills == team_1_kills
          kills_remaining = @tournament_max_kills - (team_0_kills > team_1_kills ? team_0_kills : team_1_kills)

          if @tournament_last_announced_kills_remaining != kills_remaining && @tournament_announce_kills_remaining_at.find { |i| i == kills_remaining }
            @tournament_last_announced_kills_remaining = kills_remaining

            broadcast_message("[Tournament] The #{Teams.name(killer.team)} need #{kills_remaining} more kills to win!", **@message_color)
          end

          if @tournament_leading_team != winning_team
            last_winning_team = @tournament_leading_team
            @tournament_leading_team = winning_team

            case winning_team
            when -1
              if last_winning_team != -1
                last_losing_team = (last_winning_team + 1) % 2
                broadcast_message("[Tournament] The #{Teams.name(last_losing_team)} have tied the game with #{@tournament_kills[:"team_#{last_losing_team}"]} kills!", **@message_color)
              else
                broadcast_message("[Tournament] Game tied with #{team_0_kills} kills!", **@message_color)
              end
            when 0
              broadcast_message("[Tournament] The #{Teams.name(0)} have taken the lead with #{team_0_kills} kills!", **@message_color)
            when 1
              broadcast_message("[Tournament] The #{Teams.name(1)} have taken the lead with #{team_1_kills} kills!", **@message_color)
            end
          end

        elsif @last_man_standing
          already_ghost = @ghost_players[killed.id]
          @ghost_players[killed.id] = killed.team unless already_ghost # Team of player at death
          is_ghost = @ghost_players[killed.id]

          # Change ghost back to a teamed team so that they spawn nicely
          # The :created event will change them back to team 3
          log("[FULL] Ghost Original Team: #{killed.name} team #{Teams.name(@ghost_players[killed.id])}") if is_ghost
          log("[FULL] _____ Original Team: #{killed.name} team #{Teams.name(@ghost_players[killed.id])}") unless is_ghost
          killed.change_team(@ghost_players[killed.id]) if is_ghost

          broadcast_message("[Tournament] #{killed.name} has become a ghost!", **@message_color)
          page_player(killed.name, "You've become a ghost, go forth and haunt the living!")
          play_sound(:lastmanstanding_new_ghost)

        elsif @infection
          handle_infection_death(killed)
        end
      # Ghosts are on the same team
      elsif (killed && killer) && killed.team == killer.team && killed.name != killer.name
        killed = PlayerData.player(PlayerData.name_to_id(killed_obj[:name]))

        if @last_man_standing
          already_ghost = @ghost_players[killed.id]

          # Change ghost back to a teamed team so that they spawn nicely
          # The :created event will change them back to team 3
          log("[PART] Ghost Original Team: #{killed.name} team #{Teams.name(@ghost_players[killed.id])}") if already_ghost
          log("[PART] _____ Original Team: #{killed.name}") unless already_ghost
          killed.change_team(already_ghost) if already_ghost
        end
      end
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
            broadcast_message("[Tournament] The #{Teams.name(winning_team)} have won the Tournament with #{highest_kill_count} kills to the #{Teams.name(losing_team)} #{@tournament_kills[:"team_#{losing_team}"]} kills!", **@message_color)
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
      # @building_damage_warnings.each do |nickname, hash|
      #   if hash[:frozen] && monotonic_time - hash[:frozen_at] >= @building_damage_freeze_duration
      #     player = PlayerData.player(PlayerData.name_to_id(nickname))

      #     if player
      #       page_player(player.name, "[Tournament] You have been unfrozen!")
      #       RenRem.cmd("UnFreezePlayer #{player.id}")

      #       hash[:frozen] = false
      #       hash[:frozen] = false
      #       hash[:warnings] = 0
      #       hash[:damage] = 0
      #     end
      #   end
      # end
    end
  end

  command(:score, arguments: 0, help: "!score - Reports the score of the current Tournament game") do |command|
    if tournament_active?
      page_player(command.issuer.name, "[Tournament] The #{Teams.name(0)} have #{@tournament_kills[:team_0]} and the #{Teams.name(1)} have #{@tournament_kills[:team_1]} kills!", **@message_color)
    else
      page_player(command.issuer.name, "[Tournament] No active tournament game!", **@message_color)
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

    @auto_game_mode_round_duration = duration

    try_start_auto_game_mode(:tournament, duration)
  end

  command(:auto_lastmanstanding, aliases: [:autolms], arguments: 0..1, help: "!auto_lastmanstanding [<duration in minutes>] - Starts a Last Man Standing game that will cycle through configured presets", groups: [:admin, :mod, :director]) do |command|
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    @auto_game_mode_round_duration = duration

    try_start_auto_game_mode(:last_man_standing, duration)
  end

  command(:auto_infection, aliases: [:autoi], arguments: 0..1, help: "!auto_infection [<duration in minutes>] - Starts an Infection game that will cycle through configured presets", groups: [:admin, :mod, :director]) do |command|
    duration = command.arguments.last.to_i
    duration = (@round_duration / 60) if duration.zero? || duration.negative?

    @auto_game_mode_round_duration = duration

    try_start_auto_game_mode(:infection, duration)
  end
end
