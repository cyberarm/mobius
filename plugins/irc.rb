mobius_plugin(name: "IRC", database_name: "irc", version: "0.0.1") do
  def ssl_default_context
    ssl_verify_peer_and_hostname
  end

  def ssl_verify_peer_and_hostname
    ssl_verify_peer.tap do |context|
      context.verify_hostname = true
    end
  end

  def ssl_verify_peer
    ssl_no_verify.tap do |context|
      context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      context.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
    end
  end

  def ssl_verify_hostname_only
    ssl_no_verify.tap do |context|
      context.verify_hostname = true
    end
  end

  def ssl_no_verify
    OpenSSL::SSL::SSLContext.new
  end

  def dial(hostname, port = 6697, local_host: nil, local_port: nil, ssl_context: ssl_default_context)
    log "Connecting to server..."

    Socket.tcp(hostname, port, local_host, local_port, connect_timeout: 10).then do |socket|
      if ssl_context
        @ssl_socket = true

        if @account_use_client_cert
          ssl_context.add_certificate(
            OpenSSL::X509::Certificate.new(File.read("#{ROOT_PATH}/conf/mobius_tls_pub.pem")),
            OpenSSL::PKey::RSA.new(File.read("#{ROOT_PATH}/conf/mobius_tls.pem"))
          )
        end

        ssl_context = SSL.send(ssl_context) if ssl_context.is_a?(Symbol)

        OpenSSL::SSL::SSLSocket.new(socket, ssl_context).tap do |ssl_socket|
          ssl_socket.hostname = hostname
          ssl_socket.connect
        end
      else
        socket
      end
    end
  rescue SystemCallError, StandardError => e
    log e
    e.backtrace.each do |line|
      log line
    end

    nil
  end

  def handle_message(raw)
    msg = IRCParser::Message.parse(raw)

    # pp msg

    case msg.command.to_s.strip.downcase
    when "ping"
      handle_ping(msg)
    when "001" # Welcome
      handle_welcome(msg)
    when "464" # ERR_PASSWDMISMATCH
      log "ERROR:Password Mismatch: #{msg.parameters.last}"
      close_socket
    when "433" # Nickname in use error
      handle_nickname_in_use(msg)
    when "error" # something went fatally wrong, we've been disconnected.
      # TODO: Probably call close socket, or do nothing?
      log "ERROR: #{msg.parameters.last}"
      close_socket
    when "353" # List of names in channel
      handle_names_list(msg)
    when "311" # WHOIS reply
      handle_whois(msg)
    when "276"
      handle_whois_cert_fingerprint(msg)
    when "mode" # a mode has moded
      handle_mode(msg)
    when "privmsg" # we've gotten a message
      handle_privmsg(msg)
    when "join" # a wild user joins
      handle_join(msg)
    when "part" # a tame user departs
      handle_part(msg)
    end
  end

  def handle_ping(msg)
    pong = IRCParser::Message.new(command: "PONG", parameters: [msg.parameters.first.strip])
    @socket.puts(pong)
    @socket.flush
  end

  def handle_welcome(msg)
    @command_queue << IRCParser::Message.new(command: "OPER", parameters: [@operator_username, @operator_password]) if !@operator_username.empty? && !@operator_password.empty?

    join_channels

    message = "Entry point found, Mobius v#{Mobius::VERSION} ready! Type !help for a list of available commands."

    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_public[:name], message])
    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_admin[:name], message])

    log "Connected!"
  end

  # FIXME
  def handle_nickname_in_use(msg)
  end

  def handle_names_list(msg)
    _nick, _privacy, channel, names = msg.parameters
    names = names.strip

    names.split(" ").each do |name|
      add_irc_user(name, channel)
    end
  end

  def handle_whois(msg)
    # msg.parameters.each.each do |value|
    # end
  end

  def handle_whois_cert_fingerprint(msg)
    _my_nick, nickname, fingerprint = msg.parameters
    fingerprint = fingerprint.strip.split(" ").last

    @irc_users[nickname] ||= {}
    @irc_users[nickname][:fingerprint] = fingerprint
  end

  def handle_mode(msg)
  end

  def handle_privmsg(msg)
    pm = false
    nickname = msg.prefix.nick
    channel = nil
    message = msg.parameters.last

    if msg.parameters.first.start_with?("#")
      channel = msg.parameters.first
    else
      pm = true
    end

    # TODO: handle CTCP?

    # Actual PRIVATE MESSAGE
    # if pm
    #   # echo for now
    #   irc_pm(nickname, message)

    #   return
    # end

    # CHANNEL MESSAGE
    # ignore messages from channels we don't care about
    return unless (channel == @channels_admin[:name] || channel == @channels_public[:name]) || pm

    fake_player = PlayerData::Player.new(
      origin: :irc,
      id: -127,
      name: nickname,
      join_time: 0,
      score: 0,
      team: 2,
      ping: 0,
      address: "10.10.10.10;11999",
      kbps: 0,
      rank: 0,
      kills: 0,
      deaths: 0,
      money: 0,
      kd: 0,
      time: 0,
      last_updated: monotonic_time
    )

    fake_player.set_value(:_irc_channel, channel)

    irc_user_role(fake_player)

    PluginManager.handle_command(fake_player, message)
  end

  def handle_join(msg)
    # A user has joined one of our channels
    channel = msg.parameters.first.strip
    nickname = msg.prefix.nick

    add_irc_user(nickname, channel)

    log "#{nickname} joined channel #{channel}"
  end

  def handle_part(msg)
    channel, _leave_message = msg.parameters
    nickname = msg.prefix.nick

    delete_irc_user(nickname, channel)

    log "#{nickname} joined channel #{channel}"
  end

  def authenticate_to_server
    messages = []
    messages << IRCParser::Message.new(command: "CAP", parameters: ["LS 302"])
    messages << IRCParser::Message.new(command: "PASS", parameters: [@account_password]) if @account_password.length.positive?
    messages << IRCParser::Message.new(command: "NICK", parameters: [@account_username])
    messages << IRCParser::Message.new(command: "USER", parameters: [@account_username, "0", "*", ":#{@account_username}"])
  end

  def add_irc_user(nickname, channel)
    admin_channel = channel == @channels_admin[:name]

    channel_level = nil
    if nickname.start_with?(/\@|\%|\+|\&|\~/)
      channel_level = nickname[0]
      nickname = nickname[1..]
    end

    @channels[admin_channel ? :admin : :public][:users][nickname] ||= {}
    @channels[admin_channel ? :admin : :public][:users][nickname][:level] ||= channel_level

    @irc_users[nickname] ||= {}
    @irc_users[nickname][:channels] ||= []
    @irc_users[nickname][:channels] << (admin_channel ? :admin : :public)
    @irc_users[nickname][:channels].uniq!

    # Send WHOIS to fetch client certificate fingerprint in order to authenticate them
    if @irc_users[nickname][:fingerprint].nil? && nickname != @account_username
      @command_queue << IRCParser::Message.new(command: "WHOIS", parameters: [nickname])
    end
  end

  def delete_irc_user(nickname, channel)
    admin_channel = channel == @channels_admin[:name]

    if (user = @irc_users[nickname])
      user[:channels].delete(admin_channel ? :admin : :public)
    end

    @channels[admin_channel ? :admin : :public][:users].delete(nickname)
  end

  def irc_broadcast(message, channel = nil)
    if channel
      @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_public[:name], message]) if channel == :public
      @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_admin[:name], message]) if channel == :admin
    else
      @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_public[:name], message])
      @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_admin[:name], message])
    end
  end

  def irc_pm(nickname, message)
    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [nickname, message])
  end

  def irc_notice(nickname, message)
      @command_queue << IRCParser::Message.new(command: "NOTICE", parameters: [nickname, message])
  end

  def irc_user_role(player)
    irc_user = @irc_users[player.name]
    found = false
    return player unless irc_user

    Config.staff.each do |level, list|
      list.each do |hash|
        next unless hash[:irc_fingerprints].to_a.find { |fingerprint| irc_user[:fingerprint] == fingerprint}
        next if player.administrator? && level == :admin
        next if player.moderator? && level == :mod
        next if player.director? && level == :director

        case level
        when :admin
          player.set_value(:administrator, true)
          :admin
        when :mod
          player.set_value(:moderator, true)
          :mod
        when :director
          player.set_value(:director, true)
          :director
        end

        break if found
      end

      break if found
    end

    player
  end

  def join_channels
    messages = []

    messages << IRCParser::Message.new(command: "JOIN", parameters: @channels_public[:key].empty? ? [@channels_public[:name]] : [@channels_public[:name], @channels_public[:key]])
    messages << IRCParser::Message.new(command: "JOIN", parameters: @channels_admin[:key].empty? ? [@channels_admin[:name]] : [@channels_admin[:name], @channels_admin[:key]])
  end

  def leave_channels_and_quit
    # TODO: Leave channels?

    @socket.puts(
      IRCParser::Message.new(command: "QUIT", parameters: ["Entering the infinite void... Quiting."])
    )

    @socket.flush
  end

  def close_socket
    return unless @socket

    if @ssl_socket
      @socket.sync_close = true
      @socket.sysclose
    else
      @socket.close
    end

    @socket = nil
  end

  def setup_and_dial
    @server_hostname = config.dig(:server, :hostname)
    @server_port = config.dig(:server, :port).to_i
    @server_use_ssl = config.dig(:server, :use_ssl) || @server_port == 6697
    @server_verify_cert = config.dig(:server, :verify_cert)

    @account_username = config.dig(:account, :username) || ""
    @account_password = config.dig(:account, :password) || ""
    @account_fingerprint = config.dig(:account, :fingerprint) || ""
    @account_use_client_cert = config.dig(:account, :use_client_cert) || false

    @operator_username = config.dig(:operator, :username) || ""
    @operator_password = config.dig(:operator, :password) || ""

    @channels_public = config.dig(:channels, :public)
    @channels_admin = config.dig(:channels, :admin)

    @irc_users = {}
    @channels = {}
    @channels[:public] = {
      users: {}
    }
    @channels[:admin] = {
      users: {}
    }

    @priority_command_queue = []
    @command_queue = []

    @ssl_context = false
    @ssl_context = @server_verify_cert ? ssl_default_context : ssl_no_verify if @server_use_ssl

    @socket = dial(
      @server_hostname,
      @server_port,
      ssl_context: @ssl_context
    )

    if @socket
      authenticate_to_server
    else
      @schedule_reconnect = 15 # seconds
    end
  end

  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

    setup_and_dial
  end

  on(:tick) do
    unless @socket
      if @schedule_reconnect
        @schedule_reconnect -= 1
        setup_and_dial if @schedule_reconnect == 0
      end

      next
    end

    begin
      while (@socket && (msg = @command_queue.shift))
        @socket.puts(msg)
      end
      @socket.flush if @socket

      # Drain messages from IRC server
      while(@socket && (raw = @socket.read_nonblock(8192)))
        # Split up messages by TCP newline (\r\n)
        raw.split("\r\n").each do |msg|
          handle_message(msg)
        end
      end
    rescue IO::WaitReadable
    rescue EOFError
    rescue SystemCallError
      close_socket

      @schedule_reconnect = 15 # seconds
    end
  end

  on(:shutdown) do
    next unless @socket

    leave_channels_and_quit

    close_socket
  end

  on(:irc_broadcast) do |message, red, green, blue|
    # Treat white as default color and don't do anything
    color = ((red.nil? || green.nil? || blue.nil?) || (red.to_i + green.to_i + blue.to_i >= 255 * 3)) ? nil : Color.new(red:, green:, blue:)
    irc_broadcast(Color.irc_colorize(color, message)) if color
    irc_broadcast(message) unless color
  end

  on(:irc_team_message) do |team_id, message, red, green, blue|
    # Treat white as default color and use team color
    color = ((red.nil? || green.nil? || blue.nil?) || (red.to_i + green.to_i + blue.to_i >= 255 * 3)) ? Teams.rgb_color(team_id) : Color.new(red:, green:, blue:)
    irc_broadcast(Color.irc_colorize(color, message), :admin)
  end

  on(:irc_admin_message) do |message, red, green, blue|
    # Treat white as default color and don't do anything
    color = ((red.nil? || green.nil? || blue.nil?) || (red.to_i + green.to_i + blue.to_i >= 255 * 3)) ? nil : Color.new(red:, green:, blue:)
    irc_broadcast(Color.irc_colorize(color, message), :admin) if color
    irc_broadcast(message, :admin) unless color
  end

  on(:irc_pm) do |player, message, red, green, blue|
    # Treat white as default color and don't do anything
    color = ((red.nil? || green.nil? || blue.nil?) || (red.to_i + green.to_i + blue.to_i >= 255 * 3)) ? nil : Color.new(red:, green:, blue:)
    irc_pm(player.name, Color.irc_colorize(color, message)) if color
    irc_pm(player.name, message) unless color
  end

  on(:player_joined) do |player|
    irc_broadcast(Teams.colorize(player.team, "#{player.name} has joined the game on team #{Color.irc_bold("#{Teams.name(player.team)}")}"))
  end

  on(:player_left) do |player|
    irc_broadcast(Teams.colorize(player.team, "#{player.name} has left the game from team #{Color.irc_bold("#{Teams.name(player.team)}")}"))
  end

  on(:chat) do |player, message|
    irc_broadcast("#{Teams.colorize(player.team, "#{Color.irc_bold("<#{player.name}>")}")} #{message}")
  end

  on(:team_chat) do |player, message|
    irc_broadcast(Teams.colorize(player.team, "#{Color.irc_bold("<#{player.name}>")} #{message}"), :admin)
  end

  on(:log) do |message|
    begin
      irc_broadcast(Color.irc_colorize(Color.new(0xd2d2d2), "#{message}"), :admin) if @socket
    rescue => e
      puts e
      puts e.backtrace
    end
  end

  # command(:message, aliases: [:msg], arguments: 1, help: "Send a public message from IRC/remote", groups: [:admin, :mod, :director]) do |command|
  #   if command.issuer.irc?
  #     broadcast_message("<#{command.issuer.name}@IRC> #{message}")
  #   else
  #     message_player(command.issuer, "Command only available from IRC/remote.")
  #   end
  # end

  # command(:game_info, aliases: [:gi], arguments: 1, help: "Send a public message from IRC/remote") do |command|
  #   if command.issuer.irc?
  #     irc_broadcast(Teams.colorize(player.team, "#{Color.irc_bold("<#{player.name}>")} #{message}"))
  #   else
  #     message_player(command.issuer, "Command only available from IRC/remote.")
  #   end
  # end

  # command(:player_info, aliases: [:pi], arguments: 1, help: "Send a public message from IRC/remote", groups: [:admin, :mod]) do |command|
  #   if command.issuer.irc?
  #     irc_broadcast(Teams.colorize(player.team, "#{Color.irc_bold("<#{player.name}>")} #{message}"))
  #   else
  #     message_player(command.issuer, "Command only available from IRC/remote.")
  #   end
  # end
end
