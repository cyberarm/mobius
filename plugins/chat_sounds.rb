mobius_plugin(name: "ChatSounds", database_name: "chat_sounds", version: "0.0.1") do
  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    @chat_sound_cooldowns = {}
    @cooldown_interval = 1.5 # seconds
  end

  on(:chat) do |player, message|
    try_send_chat_sound(player, message)
  end

  on(:team_chat) do |player, message|
    try_send_chat_sound(player, message, teamed: true)
  end

  command(:sounds, arguments: 0..1, help: "!sounds [on|off] - List available sounds or toggle sounds for yourself") do |command|
    argument = command.arguments.first.to_s.downcase.strip
    if argument.empty?
      config["sounds"].map { |h| h["message"] }.each_slice(10) do |slice|
        message_player(command.issuer, slice.join(", "))
      end

      next
    end

    case argument
    when "on"
      database_remove(player.name)
    when "off"
      database_set(player.name, "disabled")
    end
  end

  def try_send_chat_sound(player, message, teamed: false)
    cooldown = @chat_sound_cooldowns[player.name]
    return if cooldown && monotonic_time < cooldown

    sound = config["sounds"].find { |msg, snd| msg == message.downcase.strip }

    return unless sound

    send_chat_sound(sound: sound["sound"], team: teamed ? player.team.id : nil)
    @chat_sound_cooldowns[player.name] = monotonic_time + @cooldown_interval
  end

  def send_chat_sound(sound:, team: nil, player: nil)
    return unless sound

    cmd = if player
            "snd #{player}"
          elsif team
            "sndt #{team}"
          else
            "snda"
          end

    RenRem.cmd(format("%s %s", cmd, sound))
  end
end
