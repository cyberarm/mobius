mobius_plugin(name: "AutoAnnounce", database_name: "auto_announce", version: "0.0.1") do
  def broadcast_announcement
    saying = @sayings[@index]
    @index += 1
    @index = 0 if @index >= @sayings.count

    return unless saying

    if saying.is_a?(String)
      broadcast_message("[MOBIUS] #{saying}", red: 255, green: 127, blue: 0)
    else
      broadcast_message("[MOBIUS] #{saying.call}", red: 255, green: 127, blue: 0)
    end
  end

  def join_announcements(player)
    @join_announcements.each do |message|
      broadcast_message("[MOBIUS] #{message}", red: 255, green: 127, blue: 0)
    end
  end

  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    @start_time = monotonic_time
    @index = 0
    @sayings = []

    config[:messages]&.each do |message|
      begin
        if message.start_with?("!proc ")
          @sayings << proc { instance_eval("\"#{message.sub("!proc ", "")}\"") }
        elsif message.start_with?("!")
          @sayings << instance_eval("\"#{message.sub("!", "")}\"")
        else
          @sayings << message
        end
      rescue => e
        log "Invalid message: #{message}"
        log e
        puts e.backtrace
      end
    end

    @rules = config[:rules] || []
    @join_announcements = config[:join_announcements] || []

    broadcast_announcement

    every(200) do
      broadcast_announcement
    end
  end

  on(:player_joined) do |player|
    # Prevent spamming the server when the bot is restarted
    join_announcements(player) unless monotonic_time - @start_time <= 1.0
  end

  command(:rules, help: "Show server rules") do |command|
    @rules.each do |line|
      broadcast_message("[MOBIUS] #{line}", red: 255, green: 127, blue: 0)
    end
  end
end
