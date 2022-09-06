mobius_plugin(name: "AutoAnnounce", version: "0.0.1") do
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

  on(:start) do
    @index = 0
    @sayings = [
      "This server is running Mobius v#{Mobius::VERSION}",
      "APB with 100% more coop!",
      "Report issues or concerns to @cyberarm on the W3D Hub discord server",
      proc { "The server time is: #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')} UTC" }
    ]

    broadcast_announcement

    every(200) do
      broadcast_announcement
    end
  end
end
