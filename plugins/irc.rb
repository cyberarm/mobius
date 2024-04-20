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
  rescue StandardError => e
    log e
    log e.backtrace

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
    when "433" # Nickname in use error
      handle_nickname_in_use(msg)
    when "error" # something went fatally wrong, we've been disconnected.
      # TODO: Probably call close socket, or do nothing?
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
    if pm
      # echo for now
      irc_pm(nickname, message)

      return
    end

    # CHANNEL MESSAGE
    # ignore messages from channels we don't care about
    return unless channel == @channels_admin[:name] || channel == @channels_public[:name]

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

    while (msg = messages.shift)
      @socket.puts(msg)
    end

    @socket.flush
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

    while (msg = messages.shift)
      @socket.puts(msg)
    end

    @socket.flush
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

    @account_username = config.dig(:account, :username)
    @account_password = config.dig(:account, :password)
    @account_fingerprint = config.dig(:account, :fingerprint)
    @account_use_client_cert = config.dig(:account, :use_client_cert)

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

    authenticate_to_server
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

    while (@socket && (msg = @command_queue.shift))
      @socket.puts(msg)
    end
    @socket.flush if @socket

    begin
      # FIXME: Buffer input and only feed complete lines to #handle_message

      # Drain messages from IRC server
      while(@socket && (raw = @socket.read_nonblock(8192)))
        # Split up messages by TCP newline (\r\n)
        raw.split("\r\n").each do |msg|
          handle_message(msg)
        end
      end
    rescue IO::WaitReadable
    rescue EOFError
      close_socket

      # TODO: Attempt to reconnect after 5, 10, 30, 60, 120 seconds, then abort.
      @schedule_reconnect = 15 # seconds
    end
  end

  on(:shutdown) do
    next unless @socket

    leave_channels_and_quit

    close_socket
  end

  on(:irc_broadcast) do |message, red, green, blue|
    irc_broadcast(message)
  end

  on(:irc_team_message) do |team_id, message, red, green, blue|
    irc_broadcast(message, :admin)
  end

  on(:irc_pm) do |player, message, red, green, blue|
    irc_pm(player.name, message)
  end

  on(:player_joined) do |player|
    irc_broadcast("#{player.name} has joined the game on team #{Teams.name(player.team)}")
  end

  on(:player_left) do |player|
    irc_broadcast("#{player.name} has left the game from team #{Teams.name(player.team)}")
  end

  on(:chat) do |player, message|
    irc_broadcast("<#{player.name}> #{message}")
  end

  on(:team_chat) do |player, message|
    irc_broadcast("<#{player.name}> #{message}", :admin)
  end
end
