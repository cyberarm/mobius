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
          log "ERROR", "#{e.class}: #{e}"
          formatted_backtrace(plugin, e.backtrace)

          # Don't raise again since we want to use our own backtrace printer
          exit
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

      ### Save list of commands to file
      # File.open("_mobius_commands.txt", "a+") do |f|
      #   f.puts "!#{command.name}"
      #   f.puts "    Help: #{command.help}"
      #   f.puts "    Aliases: #{command.aliases.map { |a| "!#{a}" }.join(', ')}"
      #   f.puts "    Groups: #{command.groups.join(', ')}"
      #   f.puts
      # end

      command.aliases.each do |comm|
        _register_command(comm, command)
      end
    end

    def self._register_command(name, command)
      existing_command = @commands[name]

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{name}' but it is reserved" if [:help, :fds, :reload_config, :enable, :reload_plugin, :disable].include?(name)

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
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_help_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :fds && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_fds_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :reload_config && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_reload_config_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :plugins && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_plugins_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :enable && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_enable_plugin_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :reload_plugin && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_reload_plugin_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :disable && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_disable_plugin_command(player, parts)

        return
      end

      command = @commands[cmd.downcase.to_sym]

      if command.nil? || !player.in_group?(command&.groups)
        log "PLUGIN MANAGER", "Player #{player.name} tried to use command #{message}"

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
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"

        command.block&.call(CommandResult.new(player, arguments))
      rescue StandardError => e
        log "PLUGIN MANAGER", "An error occurred while delivering command: #{command.name}, to plugin: #{command.plugin.___name}"
        log "ERROR", "#{e.class}: #{e}"
        formatted_backtrace(command.plugin, e.backtrace)
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
          cmd_prefix_length = "cmsgp #{player.id} 255,127,0 [MOBIUS] ".length
          if command.help.length + cmd_prefix_length > 249
            current_chunk = 0
            chunk_size = (249 - cmd_prefix_length)

            while (chunk = command.help[current_chunk...(current_chunk + chunk_size)])
              current_chunk += chunk_size
              RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{chunk}")
            end
          else
            RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{command.help}")
          end
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
      # If part starts with magic character, assume a nickname follows and replace it with the player's ID
      magic = parts.find { |t| t.start_with?("%") }
      command_player = PlayerData.player(PlayerData.name_to_id(magic[1..magic.length - 1], exact_match: false)) if magic
      parts[parts.index(magic)] = "#{command_player.id}" if command_player

      # If part starts with magic characters, assume command should be issued for ALL players
      everyone_magic = parts.find { |t| t == ("%!") }
      if everyone_magic
        index = parts.index(everyone_magic)

        PlayerData.player_list.each do |ply|
          # We issue the command as normal for the issuer so skip them here
          next if ply.id == player.id

          parts[index] = ply.id
          RenRem.cmd(parts.join(" "))
        end

        parts[index] = player.id
      elsif magic && !command_player
        RenRem.cmd("ppage #{player.id} Command aborted. Could not find player with nickname matching: #{magic.sub('%', '')}")

        return
      end

      RenRem.cmd(parts.join(" ")) do |response|
        response.each_line do |line|
          next if line.strip.empty?

          RenRem.cmd("ppage #{player.id} #{line}")
        end
      end
    end

    def self.handle_reload_config_command(player, parts)
      RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Reloading config...")
      Config.reload_config
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

      exact_match_plugin = @plugins.find { |plugin| !plugin.___enabled? && plugin.___name.downcase == name.downcase }
      found_plugins = @plugins.select { |plugin| !plugin.___enabled? && plugin.___name.downcase.include?(name.downcase) }

      if found_plugins.size == 1 || exact_match_plugin
        plugin = exact_match_plugin || found_plugins.first
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Enabling plugin: #{plugin.___name}")
        enable_plugin(plugin)

      elsif found_plugins.size > 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Found multiple plugins: #{found_plugins.map(&:___name).join(', ')}")

      else
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No disabled plugins matching: #{name}.")
      end
    end

    def self.handle_reload_plugin_command(player, parts)
      name = parts[0]

      if name.nil?
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] !reload_plugin <plugin name>")

        return
      end

      exact_match_plugin = @plugins.find { |plugin| plugin.___name.downcase == name.downcase }
      found_plugins = @plugins.select { |plugin| plugin.___name.downcase.include?(name.downcase) }

      if found_plugins.size == 1 || exact_match_plugin
        plugin = exact_match_plugin || found_plugins.first
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Reloading plugin: #{plugin.___name}")
        reload_plugin(plugin)

      elsif found_plugins.size > 1
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Found multiple plugins: #{found_plugins.map(&:___name).join(', ')}")

      else
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No plugins matching: #{name}.")
      end
    end

    def self.handle_disable_plugin_command(player, parts)
      name = parts[0]

      if name.nil?
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] !disable <plugin name>")

        return
      end

      exact_match_plugin = @plugins.find { |plugin| plugin.___enabled? && plugin.___name.downcase == name.downcase }
      found_plugins = @plugins.select { |plugin| plugin.___enabled? && plugin.___name.downcase.include?(name.downcase) }

      if found_plugins.size == 1 || exact_match_plugin
        plugin = exact_match_plugin || found_plugins.first
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Disabling plugin: #{plugin.___name}")
        disable_plugin(plugin)

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
        formatted_backtrace(plugin, e.backtrace)
      end

      handlers = plugin.___event_handlers[event]

      return unless handlers.is_a?(Array)

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue StandardError => e
          log "PLUGIN MANAGER", "An error occurred while delivering event: #{event}, for plugin: #{plugin.___name}"
          log "ERROR", "#{e.class}: #{e}"
          formatted_backtrace(plugin, e.backtrace)
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

    def self.formatted_backtrace(plugin_or_filename, backtrace)
      backtrace.each do |line|
        line = line.sub("(eval)", "-> #{plugin_or_filename.is_a?(String) ? plugin_or_filename : plugin_or_filename.___plugin_file}")

        puts "        #{line}"
      end
    end
  end
end
