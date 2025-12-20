mobius_plugin(name: "ARYuriMode", database_name: "ar_yuri_mode", version: "0.0.1") do
  on(:start) do
    @yuri_mode = false
    @yuri_color = { red: 148, green: 40, blue: 189 }
    @yuri_mode_announce_sound = "c_initiate_created_5.wav"
    @yuri_mode_gain_teammate_sound = "c_initiate_created_3.wav"
    @yuri_mode_lose_teammate_sound = "c_initiate_killed_5.wav"
    @yuri_team = 3

    @yuri_nuke_script = "MS_Created_Apply_Damage"
    @yuri_nuke_script_params ="None,10000" # warhead and minimium damage

    @yuri_objects = {}
    @yuri_controller = "Yuri_Controller"

    @team_history = {}
  end

  on(:created) do |obj|
    @yuri_objects[obj[:object]] = obj if obj[:preset].downcase == @yuri_controller.downcase
    @yuri_objects[obj[:object]] = obj if obj[:team] == @yuri_team
  end

  on(:destroyed) do |obj|
    @yuri_objects.delete(obj[:object])
  end

  command(:yuri_mode, aliases: [:yuri], arguments: 1, help: "yuri_mode <on/off>", groups: [:admin, :mod]) do |command|
    if command.arguments.first.to_s.downcase.strip =~ /true|on|1/
      @yuri_mode = true
    else
      @yuri_mode = false
    end

    page_player(command.issuer, "Yuri Mode: #{@yuri_mode ? 'On' : 'Off'}")

    if @yuri_mode
      RenRem.cmd("spawn_object yuri_controller")
      RenRem.cmd("snda #{@yuri_mode_announce_sound}")
      broadcast_message("[Yuri Initiates] Hail to the great Yuri!", **@yuri_color)
    else
      broadcast_message(". . .", **@yuri_color)

      # Return players to their original teams
      PlayerData.players_by_team(@yuri_team).each do |player|
        player.change_team(@team_history[player.name])
      end

      # do some other stuff after other events have been processed
      after(1.0) do
        @yuri_objects.each do |key, obj|
          RenRem.cmd("AttachScriptToObject #{obj[:object]} #{@yuri_nuke_script} #{@yuri_nuke_script_params}")
        end
      end
    end
  end


  command(:yuri_me, aliases: [:ym], arguments: 0..1, help: "yuri_me [player] - Toggle whether you're on Yuri's side or soon will be...", groups: [:admin, :mod, :director]) do |command|
    unless @yuri_mode
      page_player(command.issuer, "Yuri mode is not active, issue `!yuri on` and try again.")

      next
    end

    player = command.arguments.first.to_s.empty? ? command.issuer : PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))

    if player.nil?
      page_player(command.issuer, "Player not in game or name is not unique!")
      next
    elsif !player.ingame?
      page_player(command.issuer, "Player is not in game.")
      next
    end

    if player.team != @yuri_team
      @team_history[player.name] = player.team
      RenRem.cmd("snda #{@yuri_mode_gain_teammate_sound}")
      player.change_team(@yuri_team)
      # Prevent auto coop from automatically moving player back to team.
      player.set_value(:manual_team, true)
      message_player(command.issuer, "#{player.name} has become Yuri's student!", **@yuri_color)
      page_player(player, "Welcome initiate!", **@yuri_color)
    else
      RenRem.cmd("snda #{@yuri_mode_lose_teammate_sound}")
      player.change_team(@team_history[player.name])
      player.set_value(:manual_team, false)
      message_player(command.issuer, "#{player.name} has abandoned Yuri!", **@yuri_color)
    end
  end
end
