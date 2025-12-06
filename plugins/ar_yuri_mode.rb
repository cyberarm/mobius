mobius_plugin(name: "ARYuriMode", database_name: "ar_yuri_mode", version: "0.0.1") do
  on(:start) do
    @yuri_mode = false
    @yuri_color = { red: 148, green: 40, blue: 189 }
    @yuri_mode_announce_sound = "c_initiate_created_5.wav"
  end

  command(:yuri_mode, aliases: [:ym], arguments: 1, help: "yuri_mode <on/off>", groups: [:admin, :mod]) do |command|
    if command.arguments.first.to_s.downcase.strip =~ /true|on|1/
      @yuri_mode = true
    else
      @yuri_mode = false
    end

    page_player(command.issuer, "Yuri Mode: #{@yuri_mode ? 'On' : 'Off'}")

    if @yuri_mode
      RenRem.cmd("snda #{@yuri_mode_announce_sound}")
      broadcast_message("[Yuri Initiates] Hail to the great Yuri!", **@yuri_color)
    end
  end
end
