module Mobius
  class PluginManager
    extend Common

    CommandResult = Struct.new(:issuer, :arguments)
    VoteResult = Struct.new(:issuer, :arguments, :___mode, :announcement)
    VoteResult.define_method(:validate?) do
      self.___mode == :validate
    end
    VoteResult.define_method(:commit?) do
      self.___mode == :commit
    end

    @plugins = []
    @commands = {}
    @deferred = []
    @votes = {}
    @active_vote = nil
    @active_vote_result = nil
    @active_vote_votes = {}
    @active_vote_start_time = 0
    @last_active_vote_announced = 0
    @announce_active_vote_every_seconds = 30.0
    @active_vote_required_percentage = 0.69
    @active_vote_sound_effect = "private_message.wav"

    @blackboard = {}

    def self.init
      log("INIT", "Initializing plugins...")

      find_plugins
      init_plugins
    end

    def self.tick
      vote_tick
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
        rescue StandardError, ScriptError => e
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

      @votes.each do |name, vote|
        if vote.plugin == plugin
          reset_vote(reason: "Vote aborted, #{plugin.___name} plugin has been disabled or reloaded.") if @active_vote == vote

          @votes.delete(name)
        end
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

      raise "Plugin '#{command.plugin.___name}' attempted to register command '#{name}' but it is reserved" if [:help, :fds, :reload_config, :enable, :reload, :disable, :v, :vote, :yes, :no].include?(name)

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

      if cmd.downcase.to_sym == :reload && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_reload_plugin_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :disable && player.administrator?
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_disable_plugin_command(player, parts)

        return
      end

      if cmd.downcase.to_sym == :vote || cmd.downcase.to_sym == :v
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"
        handle_vote_plugin_command(player, parts)

        return
      end

      # Handle !yes and !no voting commands
      if cmd.downcase.to_sym == :yes || cmd.downcase.to_sym == :no
        log "PLUGIN MANAGER", "Player #{player.name} issued command #{message}"

        parts << cmd.downcase.strip

        handle_vote_plugin_command(player, parts)

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
      rescue StandardError, ScriptError => e
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

    def self.handle_vote_plugin_command(player, parts)
      vt = parts.shift

      unless vt
        # If a vote is active, report what it is
        if @active_vote
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Active vote: #{@active_vote_result.announcement}")

        # If not, return list of available votes
        else
          handle_vote_help(player, parts)
        end

        return
      end

      case vt.downcase.to_sym
      when :y, :yes
        unless @active_vote
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No active vote")

          return
        end

        # Already voted, yes.
        unless @active_vote_votes[player.name]
          @active_vote_votes[player.name] = true
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] You voted Yes to #{@active_vote.name}")
        else
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] You already voted Yes to #{@active_vote.name}")
        end
        return
      when :n, :no
        unless @active_vote
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] No active vote")

          return
        end

        # Already voted, no.
        unless @active_vote_votes[player.name] == false
          @active_vote_votes[player.name] = false
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] You voted No to #{@active_vote.name}")
        else
          RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] You already voted No to #{@active_vote.name}")
        end
        return
      end

      if @active_vote
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] A vote is already active: #{@active_vote_result.announcement}")

        return
      end

      vote = @votes[vt.downcase.to_sym]

      if vote.nil? || !player.in_group?(vote&.groups)
        log "PLUGIN MANAGER", "Player #{player.name} tried to use vote #{parts.join(' ')}"

        RenRem.cmd("cmsgp #{player.id} 255,255,255, vote: #{vt} not found.")

        return
      end

      arguments = []
      vote_arguments = vote.arguments.is_a?(Range) ? vote.arguments.max : vote.arguments

      if parts.count.zero? && vote_arguments.zero? && parts.count.zero?
        # Do nothing here, vote has no arguments and we've received no arguments
      elsif vote.arguments.is_a?(Range) ? parts.count >= vote.arguments.min : parts.count >= vote_arguments
        (vote_arguments - 1).times do
          arguments << parts.shift
        end

        arguments << parts.join(" ")
      else
        RenRem.cmd("cmsgp #{player.id} 255,255,255 wrong number of arguments provided.")
        RenRem.cmd("cmsgp #{player.id} 255,255,255 #{vote.description}")

        return
      end

      begin
        vote_result = VoteResult.new(player, arguments, :validate, vote.description)
        result = vote.block&.call(vote_result)

        pp [vote_result, result]

        if result
          @active_vote = vote
          @active_vote_result = vote_result
          @last_active_vote_announced = monotonic_time
          @active_vote_start_time = monotonic_time

          RenRem.cmd("evaa #{@active_vote_sound_effect}")
          RenRem.cmd("cmsg 64,255,64 [MOBIUS] A vote is active: #{@active_vote_result.announcement}")
        end
      rescue StandardError, ScriptError => e
        log "PLUGIN MANAGER", "An error occurred while delivering vote: #{vote.name}, to plugin: #{vote.plugin.___name}"
        log "ERROR", "#{e.class}: #{e}"
        formatted_backtrace(vote.plugin, e.backtrace)
      end
    end

    def self.handle_vote_help(player, parts)
      votes = @votes.select do |name, vote|
        player.in_group?(vote.groups)
      end

      RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] Available Votes:")
      votes.map { |name, v| "#{name} - #{v.description}" }.each do |vote_info|
        RenRem.cmd("cmsgp #{player.id} 255,127,0 [MOBIUS] #{vote_info}")
      end
    end

    def self.register_vote(vote)
      _register_vote(vote.name, vote)

      ### Save list of votes to file
      # File.open("_mobius_votes.txt", "a+") do |f|
      #   f.puts "!#{vote.name}"
      #   f.puts "    Description: #{vote.description}"
      #   f.puts "    Aliases: #{vote.aliases.map { |a| "!#{a}" }.join(', ')}"
      #   f.puts "    Groups: #{vote.groups.join(', ')}"
      #   f.puts
      # end

      vote.aliases.each do |vt|
        _vote_command(vt, vote)
      end
    end

    def self._register_vote(name, vote)
      existing_vote = @votes[name]

      raise "Plugin '#{vote.plugin.___name}' attempted to register vote '#{name}' but it is reserved" if [:y, :yes, :n, :no].include?(name)

      raise "Plugin '#{vote.plugin.___name}' attempted to register vote '#{existing_vote.name}' but it's already registered to '#{existing_vote.plugin.___name}'" if existing_vote

      @votes[name] = vote
    end

    def self.vote_tick
      return unless @active_vote

      seconds = monotonic_time

      if seconds - @active_vote_start_time >= @active_vote.duration
        reset_vote(reason: "Vote has timed out.")

        return
      end

      if seconds - @last_active_vote_announced >= @announce_active_vote_every_seconds
        @last_active_vote_announced = seconds

        RenRem.cmd("evaa #{@active_vote_sound_effect}")
        RenRem.cmd("cmsg 64,255,64 [MOBIUS] A vote is active: #{@active_vote_result.announcement}")
      end

      player_list = PlayerData.player_list.select(&:ingame?)
      required_votes = (player_list.size * @active_vote_required_percentage).ceil
      positive_votes = player_list.select { |ply| @active_vote_votes[ply.name] == true }.size
      negative_votes = player_list.select { |ply| @active_vote_votes[ply.name] == false }.size
      total_votes = positive_votes + negative_votes

      vote_passed = false
      vote_failed = total_votes >= player_list.size

      if positive_votes >= required_votes
        log("PLUGIN MANAGER", "Passing Vote [#{@active_vote.name}]: #{player_list.size} Players, #{total_votes} Total votes, #{required_votes} Required votes, #{positive_votes} Ayes, #{negative_votes} Nays, and #{player_list.size - total_votes} Abstained.")
        vote_passed = true

        RenRem.cmd("evaa #{@active_vote_sound_effect}")
        RenRem.cmd("cmsg 64,255,64 [MOBIUS] Vote has PASSED! #{positive_votes} Ayes, #{negative_votes} Nays, and #{player_list.size - total_votes} Abstained.")
      end

      if vote_passed
        vote = @active_vote

        begin
          @active_vote_result.___mode = :commit

          vote.block&.call(@active_vote_result)
        rescue StandardError, ScriptError => e
          log "PLUGIN MANAGER", "An error occurred while delivering vote: #{vote.name}, to plugin: #{vote.plugin.___name}"
          log "ERROR", "#{e.class}: #{e}"
          formatted_backtrace(vote.plugin, e.backtrace)
        end

        reset_vote
        return
      end

      if vote_failed
        log("PLUGIN MANAGER", "Failing Vote [#{@active_vote.name}]: #{player_list.size} Players, #{total_votes} Total votes, #{required_votes} Required votes, #{positive_votes} Ayes, #{negative_votes} Nays, and #{player_list.size - total_votes} Abstained.")

        RenRem.cmd("evaa #{@active_vote_sound_effect}")
        reset_vote(reason: "Vote has FAILED. #{positive_votes} Ayes, #{negative_votes} Nays, and #{player_list.size - total_votes} Abstained.")

        return
      end
    end

    def self.reset_vote(reason: nil)
      @active_vote = nil
      @active_vote_result = nil
      @active_vote_votes = {}
      @active_vote_start_time = 0
      @last_active_vote_announced = 0

      RenRem.cmd("evaa #{@active_vote_sound_effect}")
      RenRem.cmd("cmsg 64,255,64 [MOBIUS] #{reason}") if reason
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
      rescue StandardError, ScriptError => e
        log "PLUGIN MANAGER", "An error occurred while delivering timer tick to plugin: #{plugin.___name}"
        log "ERROR", "#{e.class}: #{e}"
        formatted_backtrace(plugin, e.backtrace)
      end

      handlers = plugin.___event_handlers[event]

      return unless handlers.is_a?(Array)

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue StandardError, ScriptError => e
          log "PLUGIN MANAGER", "An error occurred while delivering event: #{event}, for plugin: #{plugin.___name}"
          log "ERROR", "#{e.class}: #{e}"
          formatted_backtrace(plugin, e.backtrace)
        end
      end
    end

    def self.reload_enabled_plugins!
      _plugins = @plugins.select(&:___enabled?)

      _plugins.each { |plugin| reload_plugin(plugin) }
    end

    def self.blackboard(key)
      @blackboard[key]
    end

    def self.blackboard_store(key, value)
      @blackboard[key] = value
    end

    def self.reset_blackboard!
      @blackboard = {}
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
