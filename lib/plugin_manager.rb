module Mobius
  class PluginManager
    CommandResult = Struct.new(:issuer, :arguments)

    @plugins = []
    @commands = {}
    @deferred = []

    @blackboard = {}

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
          puts e.backtrace
        end
      end
    end

    def self.register_plugin(plugin_file)
      @plugins << Plugin.new(plugin_file)

      log "PLUGIN MANAGER", "Found plugin: #{@plugins.last.___name}"
    end

    def self.init_plugins
      @plugins.each do |plugin|
        next if Config.enabled_plugins.size.positive? && Config.enabled_plugins.find { |i| i.downcase == plugin.___name.downcase }.nil?
        next if Config.disabled_plugins.size.positive? && Config.disabled_plugins.find { |i| i.downcase == plugin.___name.downcase }

        enable_plugin(plugin)
      end
    end

    def self.enable_plugin(plugin)
      plugin.___enable_plugin

      log "PLUGIN MANAGER", "Enabled plugin: #{plugin.___name}"

      deliver_event(plugin, :start, nil)
    end

    def self.reload_plugin(plugin)
      disable_plugin(plugin)

      new_plugin = Plugin.new(plugin.___plugin_file)
      @plugins[@plugins.index(plugin)] = new_plugin

      enable_plugin(new_plugin)
    end

    def self.disable_plugin(plugin)
      deliver_event(plugin, :shutdown, nil)

      plugin.___disable_plugin

      @commands.each do |name, command|
        @commands.delete(name) if command.plugin == plugin
      end

      log "PLUGIN MANAGER", "Disabled plugin: #{plugin.___name}"
    end

    def self.register_command(command)
      _register_command(command.name, command)

      command.aliases.each do |comm|
        _register_command(comm, command)
      end
    end

    def self._register_command(name, command)
      existing_command = @commands[name]

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{name}' but it is reserved" if [:help, :fds].include?(name)

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{existing_command.name}' but it's already registered to '#{existing_command.plugin.___name}'" if existing_command

      if Config.limit_commands_to_staff_level
        case Config.limit_commands_to_staff_level.to_sym
        when :admin
          command.groups.clear
          command.groups.push(:admin)
        when :mod
          command.groups.clear
          command.groups.push(:admin, :mod)
        when :director
          command.groups.clear
          command.groups.push(:admin, :mod, :director)
        else
          raise ArgumentError, "Invalid config option 'limit_commands_to_staff_level' expected: admin, mod, or director, got: #{Config.limit_commands_to_staff_level}"
          command.groups << Config.limit_commands_to_staff_level.to_sym
        end
      end

      @commands[name] = command
    end

    def self.handle_command(player, message)
      return unless message.start_with?("!")

      parts = message.strip.split(" ")
      cmd = parts.shift.sub("!", "")

      if cmd.downcase.to_sym == :help
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"
        handle_help_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :fds && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"
        handle_fds_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :plugins && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"
        handle_plugins_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :enable && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"
        handle_enable_plugin_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :disable && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"
        handle_disable_plugin_command(player, parts)

        return
      end

      command = @commands[cmd.downcase.to_sym]

      if command.nil? || !player.in_group?(command&.groups)
        log "PLUGIN MANAGER", "Player #{player.name} tried to use command !#{cmd}"

        RenRem.cmd("cmsgp #{player.id} 255,255,255, command: #{cmd} not found.")

        return
      end

      arguments = []
      command_arguments = command.arguments.is_a?(Range) ? command.arguments.max : command.arguments

      if parts.count.zero? && command_arguments.zero? && parts.count.zero?
        # Do nothing here, command has no arguments and we've received no arguments
      elsif command.arguments.is_a?(Range) ? parts.count >= command.arguments.min : parts.count >= command_arguments
        (command_arguments - 1).times do
          arguments << parts.shift
        end

        arguments << parts.join(" ")
      else
        RenRem.cmd("cmsgp #{player.id} 255,255,255 wrong number of arguments provided.")
        RenRem.cmd("cmsgp #{player.id} 255,255,255 #{command.help}")

        return
      end

      begin
        log "PLUGIN MANAGER", "Player #{player.name} issued command !#{cmd}"

        command.block&.call(CommandResult.new(player, arguments))
      rescue StandardError => e
        log "PLUGIN MANAGER", "An error occurred while delivering command: #{command.name}, to plugin: #{command.plugin.___name}"
        log "ERROR", "#{e.class}: #{e}"
        puts e.backtrace
      end
    end

    def self.handle_help_command(player, parts)
      cmds = @commands.select do |name, cmd|
        player.in_group?(cmd.groups)
      end

      if parts.size == 1
        command = cmds.find { |name, _| name == parts.first.to_sym }

        if command
          command = command.last

          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Help for command !#{command.name}:")
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{command.help}")
        else
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Command !#{parts.first} not found.")
        end
      else
        cmds = cmds.map { |name, _| name }

        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Available Commands:")
        cmds.map { |c| "!#{c}" }.each_slice(10) do |slice|
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{slice.join(', ')}")
        end
      end
    end

    def self.handle_fds_command(player, parts)
      RenRem.cmd(parts.join(" "))
    end

    def self.handle_plugins_command(player, parts)
      enabled_plugins = @plugins.select{ |plugin| plugin.___enabled? }.map(&:___name)
      disabled_plugins = @plugins.select{ |plugin| !plugin.___enabled? }.map(&:___name)

      RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Enabled Plugins:")
      enabled_plugins.each_slice(5) do |slice|
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{slice.join(', ')}")
      end

      RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Disabled Plugins:") if disabled_plugins.size.positive?
      disabled_plugins.each_slice(5) do |slice|
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{slice.join(', ')}")
      end
    end

    def self.handle_enable_plugin_command(player, parts)
      name = parts[0]

      if name.nil?
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] !enable <plugin name>")

        return
      end

      found_plugins = @plugins.select { |plugin| !plugin.___enabled? && plugin.___name.downcase.include?(name.downcase)}

      if found_plugins.size == 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Enabling plugin: #{found_plugins.first.___name}")
        enable_plugin(found_plugins.first)

      elsif found_plugins.size > 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Found multiple plugins: #{found_plugins.map(&:___name).join(', ')}")

      else
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No disabled plugins matching: #{name}.")
      end
    end

    def self.handle_disable_plugin_command(player, parts)
      name = parts[0]

      if name.nil?
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] !disable <plugin name>")

        return
      end

      found_plugins = @plugins.select { |plugin| plugin.___enabled? && plugin.___name.downcase.include?(name.downcase)}

      if found_plugins.size == 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Disabling plugin: #{found_plugins.first.___name}")
        disable_plugin(found_plugins.first)

      elsif found_plugins.size > 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Found multiple plugins: #{found_plugins.map(&:___name).join(', ')}")

      else
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No enabled plugins matching: #{name}.")
      end
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
        next unless plugin.___enabled?

        deliver_event(plugin, event, *args)
      end
    end

    def self.deliver_event(plugin, event, *args)
      begin
        plugin.___tick if event == :tick
      rescue StandardError => e
        log "PLUGIN MANAGER", "An error occurred while delivering timer tick to plugin: #{plugin.___name}"
        log "ERROR", "#{e.class}: #{e}"
        puts e.backtrace
      end

      handlers = plugin.___event_handlers[event]

      return unless handlers.is_a?(Array)

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue StandardError => e
          log "PLUGIN MANAGER", "An error occurred while delivering event: #{event}, for plugin: #{plugin.___name}"
          log "ERROR", "#{e.class}: #{e}"
          puts e.backtrace
        end
      end
    end

    def self.blackboard(key)
      @blackboard[key]
    end

    def self.blackboard_store(key, value)
      @blackboard[key] = value
    end

    # Delay delivery of event/block until the backend has done it's thing
    def self.defer(seconds, &block)
      @deferred << Plugin::Timer.new(:after, 0, seconds, block)
    end
  end
end
