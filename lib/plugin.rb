module Mobius
  class Plugin
    include Common

    Timer = Struct.new(:type, :ticks, :delay, :block)
    Command = Struct.new(:plugin, :name, :aliases, :arguments, :help, :groups, :block)
    Vote = Struct.new(:plugin, :name, :aliases, :arguments, :duration, :description, :groups, :block)

    attr_reader :___name, :___database_name, :___version, :___event_handlers, :___timers, :___data, :___plugin_file

    # RESERVED
    def initialize(plugin_file)
      @___name = ""
      @___version = ""
      @___event_handlers = {}
      @___timers = []
      @___data = {}
      @___enabled = false
      @___plugin_file = plugin_file

      instance_eval(File.read(@___plugin_file))
    end

    # RESERVED: Enables plugin
    def ___enable_plugin
      @___enabled = true

      @___block.call
    end

    # RESERVED: Disables plugin
    def ___disable_plugin
      @___event_handlers.clear
      @___timers.clear
      @___data.clear

      @___enabled = false
    end

    # RESERVED
    def ___enabled?
      @___enabled
    end

    # RESERVED
    def mobius_plugin(name:, database_name:, version:, &block)
      @___name = name
      @___database_name = database_name
      @___version = version

      @___block = block
    end

    # RESERVED: Called by PluginManager ticker
    def ___tick
      @___timers.each do |timer|
        timer.ticks += 1

        next unless timer.ticks >= timer.delay

        case timer.type
        when :every
          timer.ticks = 0
          timer.block&.call
        when :after
          timer.block&.call

          @___timers.delete(timer)
        end
      end
    end

    # register event listener
    def on(event, &block)
      @___event_handlers[event.to_sym] ||= []

      @___event_handlers[event.to_sym] << block
    end

    # register command
    def command(name, aliases: [], arguments: 0, help:, groups: [:ingame], &block)
      PluginManager.register_command(
        Command.new(self, name, aliases, arguments, help, groups, block)
      )
    end

    # register vote
    def vote(name, aliases: [], arguments: 0, duration: 120.0, description:, groups: [:ingame], &block)
      PluginManager.register_vote(
        Vote.new(self, name, aliases, arguments, duration, description, groups, block)
      )
    end

    def every(seconds, &block)
      @___timers << Timer.new(:every, 0, seconds, block)
    end

    def after(seconds, &block)
      @___timers << Timer.new(:after, 0, seconds, block)
    end

    def kick_player!(player, message = "")
      if player
        RenRem.cmd("kick #{player.id} #{message}")
      else
        notify_moderators("Failed to kick \"#{name}\", name not found or not unique!")
      end
    end

    def temp_ban_player!(player, banner, reason, duration)
      kick_player!(player, reason)
    end

    def ban_player!(player, banner, reason)
    end

    def notify_moderators(message)
      PlayerData.player_list.each do |player|
        page_player(player, message) if player.administrator? || player.moderator?
      end
    end

    def auto_kick!(player)
    end

    def add_player_report(player, reporter, reason)
    end

    def remix_teams
      return unless ServerStatus.total_players.positive?

      noise = Perlin::Noise.new(1, seed: Time.now.to_i)
      players = PlayerData.player_list.select(&:ingame?).sort { noise[rand(-1024.1024..1024.1024)] }

      players.each_with_index do |player, i|
        player.change_team(i % 2)
      end
    end

    def remix_teams_by_skill
      return unless ServerStatus.total_players.positive?

      team_zero, team_one = Teams.skill_sort_teams
      Teams.team_first_picking = Teams.team_first_picking.zero? ? 1 : 0

      team_zero.each do |player|
        player.change_team(0)
      end

      team_one.each do |player|
        player.change_team(1)
      end
    end

    def log(message)
      Kernel.log("PLUGIN: #{@___name}", message)
    end

    def database_set(key, value)
      Database.transaction do
        if (dataset = database_get(key))
          dataset.update(value: value)
        else
          Database::PluginData.create(plugin_name: @___database_name, key: key, value: value)
        end
      end
    end

    def database_get(key)
      Database::PluginData.first(plugin_name: @___database_name, key: key)
    end

    def database_remove(key)
      if (db = database_get(key))
        db.delete
      end
    end

    def config
      config_path = "#{ROOT_PATH}/plugins/configs/#{File.basename(@___plugin_file, ".rb")}.json"
      @___config || File.exist?(config_path) ? @___config = JSON.parse(File.read(config_path), symbolize_names: true) : {}
    rescue JSON::ParserError => e
      log "Failed to parse config: #{config_path}"
      puts e
      puts e.backtrace

      {}
    end
  end
end
