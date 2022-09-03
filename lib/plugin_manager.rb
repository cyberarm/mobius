module Mobius
  class PluginManager
    CommandResult = Struct.new(:issuer, :arguments)

    @plugins = []
    @commands = {}
    @deferred = []

    def self.init
      log("INIT", "Initializing plugins...")

      find_plugins
      init_plugins
    end

    def self.teardown
      log("TEARDOWN", "Shutdown Plugins...")

      @plugins.each do |plugin|
        deliver_event(plugin, :shutdown, nil)
      end

      @deferred.clear
    end

    def self.find_plugins
      Dir.glob("#{ROOT_PATH}/plugins/*.rb").each do |plugin|
        next if File.basename(plugin).start_with?("_")

        begin
          register_plugin(plugin)
        rescue => e
          puts "Failed to load plugin: #{File.basename(plugin)}"
          raise
        end
      end
    end

    def self.register_plugin(plugin_file)
      @plugins << Plugin.new(plugin_file)
    end

    def self.init_plugins
      @plugins.each do |plugin|
        next if plugin.___data[:plugin_disabled]

        log "PLUGIN MANAGER", "Loaded plugin: #{plugin.___name}"

        deliver_event(plugin, :start, nil)
      end
    end

    def self.register_command(command)
      existing_command = @commands[command.name]

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{existing_command.name}' but it is reserved" if command.name == :help

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{existing_command.name}' but it's already registered to '#{existing_command.plugin.___name}'" if existing_command

      @commands[command.name] = command
    end

    def self.handle_command(player, message)
      return unless message.start_with?("!")

      parts = message.split(" ")
      cmd = parts.shift.sub("!", "")

      if cmd.downcase.to_sym == :help
        handle_help_command(player)

        return
      end

      command = @commands[cmd.downcase.to_sym]

      return unless command
      return unless player.in_group?(command.groups)

      arguments = []

      if parts.count >= command.arguments
        (command.arguments - 1).times do
          arguments << parts.shift
        end

        arguments << parts.join(" ")
      else
        # TODO: Send error and help
        RenRem.cmd("cmsgp #{player.id} 255,255,255 wrong number of arguments provided.")
        RenRem.cmd("cmsgp #{player.id} 255,255,255 #{command.help}")
        return
      end


      begin
        command.block&.call(CommandResult.new(player, arguments))
      rescue StandardError => e
        log "PLUGIN MANAGER", "An error occurred while delivering command: #{command.name}, to plugin: #{command.plugin.___name}"
        log "ERROR", e
      end
    end

    def self.handle_help_command(player)
      cmds = @commands.select do |name, cmd|
        player.in_group?(cmd.groups)
      end

      cmds = cmds.map { |a| a.last }

      RenRem.cmd("cmsg 255,127,0 [MOBIUS] Available Commands:")
      RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{cmds.map { |c| "!#{c.name}" }.join(', ')}")
    end

    def self.publish_event(event, *args)
      if event == :tick
        @deferred.each do |timer|
          timer.ticks += 1

          if timer.ticks >= timer.delay
            timer.block&.call
            @deferred.delete(timer)
          end
        end
      end

      @plugins.each do |plugin|
        deliver_event(plugin, event, *args)
      end
    end

    def self.deliver_event(plugin, event, *args)
      begin
        plugin.___tick if event == :tick
      rescue StandardError => e
        log "PLUGIN MANAGER", "An error occurred while delivering timer tick to plugin: #{plugin.___name}"
        log "ERROR", e
      end

      handlers = plugin.___event_handlers[event]

      return unless handlers.is_a?(Array)

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue StandardError => e
          log "PLUGIN MANAGER", "An error occurred while delivering event: #{event}, for plugin: #{plugin.___name}"
          log "ERROR", e
        end
      end
    end

    # Delay delivery of event/block until the backend has done it's thing
    def self.defer(seconds, &block)
      @deferred << Plugin::Timer.new(:after, 0, seconds, block)
    end
  end
end
