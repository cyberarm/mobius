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
    Socket.tcp(hostname, port, local_host, local_port).then do |socket|
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

  # def authenticate_with_brenbot!(socket)
  #   username = @irc_profile.username.empty? ? @irc_profile.nickname : @irc_profile.username

  #   pass = IRCParser::Message.new(command: "PASS", parameters: [Base64.strict_decode64(@irc_profile.password)]) unless @irc_profile.password.empty?
  #   user = IRCParser::Message.new(command: "USER", parameters: [username, "0", "*", ":#{@irc_profile.nickname}"])
  #   nick = IRCParser::Message.new(command: "NICK", parameters: [@irc_profile.nickname])

  #   socket.puts(pass)
  #   socket.puts(user)
  #   socket.puts(nick)

  #   socket.flush

  #   until socket.closed?
  #     raw = socket.gets
  #     next if raw.to_s.empty?

  #     msg = IRCParser::Message.parse(raw)

  #     if msg.command == "PING"
  #       pong = IRCParser::Message.new(command: "PONG", parameters: [msg.parameters.first.sub("\r\n", "")])
  #       socket.puts("#{pong}")
  #       socket.flush
  #     elsif msg.command == "001" && msg.parameters.join.include?("#{@irc_profile.nickname}!#{@irc_profile.username.split("/").first}")
  #       pm = IRCParser::Message.new(command: "PRIVMSG", parameters: [@irc_profile.bot_username, "!auth #{@irc_profile.bot_auth_username} #{Base64.strict_decode64(@irc_profile.bot_auth_password)}"])
  #       socket.puts(pm)

  #       quit = IRCParser::Message.new(command: "QUIT", parameters: ["Quiting from an Asterisk"])
  #       socket.puts(quit)
  #       socket.flush

  #       sleep 15
  #       close_socket(socket)
  #     elsif msg.command == "ERROR"
  #       close_socket(socket)
  #     end
  #   end
  # end

  def handle_message(raw)
    msg = IRCParser::Message.parse(raw)

    pp msg

    case msg.command.to_s.strip.downcase
    when "ping"
      pong = IRCParser::Message.new(command: "PONG", parameters: [msg.parameters.first.strip])
      @socket.puts(pong)
      @socket.flush
    when "001" # Welcome
      join_channels
    when "433" # Nickname in use error
    when "error" # something went fatally wrong, we've been disconnected.
    when "privmsg"
    when "join"
    when "part"
    end
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

  on(:start) do
    if config.nil? || config.empty?
      log "Missing or invalid config"
      PluginManager.disable_plugin(self)

      next
    end

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

  on(:tick) do
    next unless @socket

    while (@socket && (msg = @command_queue.shift))
      @socket.puts(msg)
    end
    @socket.flush if @socket

    begin
      # Drain messages from IRC server
      while(@socket && (raw = @socket.read_nonblock(4096)))
        handle_message(raw)
      end
    rescue IO::WaitReadable
    rescue EOFError
      close_socket

      # TODO: Attempt to reconnect after 5, 10, 30, 60, 120 seconds, then abort.
    end
  end

  on(:shutdown) do
    next unless @socket

    leave_channels_and_quit

    close_socket
  end

  on(:irc_broadcast) do |message, red, green, blue|
  end

  on(:irc_pm) do |player, message, red, green, blue|
  end

  on(:chat) do |player, message|
    msg = "<#{player.name}> #{message}"
    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_public[:name], msg])
    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_admin[:name], msg])
  end

  on(:team_chat) do |player, message|
    msg = "<#{player.name}> #{message}"
    @command_queue << IRCParser::Message.new(command: "PRIVMSG", parameters: [@channels_admin[:name], msg])
  end
end
