module Mobius
  class Plugin
    Timer = Struct.new(:type, :ticks, :delay, :block)
    Command = Struct.new(:plugin, :name, :aliases, :arguments, :help, :groups, :block)

    attr_reader :___name, :___version, :___event_handlers, :___timers, :___data, :___plugin_file

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
    def mobius_plugin(name:, version:, &block)
      @___name = name
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

    def every(seconds, &block)
      @___timers << Timer.new(:every, 0, seconds, block)
    end

    def after(seconds, &block)
      @___timers << Timer.new(:after, 0, seconds, block)
    end

    def broadcast_message(message, red: 255, green: 255, blue: 255)
      renrem_cmd("cmsg #{red},#{green},#{blue} #{message}")
    end

    def message_player(name, message, red: 255, green: 255, blue: 255)
      return unless (player_id = PlayerData.name_to_id(name))

      renrem_cmd("cmsgp #{player_id} #{red},#{green},#{blue} #{message}")
    end

    def page_player(name, message, red: 255, green: 255, blue: 255)
      return unless (player_id = PlayerData.name_to_id(name))

      renrem_cmd("ppage #{player_id} #{message}")
    end

    def renrem_cmd(data, delay = nil)
      RenRem.cmd(data, delay)
    end

    def kick_player!(name, message = "")
      exact_match = PlayerData.name_to_id(name, exact_match: true)
      partial_match = PlayerData.name_to_id(name, exact_match: false)

      if (player = PlayerData.player(exact_match.negative? ? partial_match : exact_match))
        RenRem.cmd("kick #{player.id} #{message}")
      else
        notify_moderators("Failed to kick \"#{name}\", name not found or not unique!")
      end
    end

    def temp_ban_player!(name, banner, reason, duration)
      kick_player!(name, reason)
    end

    def ban_player!(name, banner, reason)
    end

    def notify_moderators(message)
    end

    def auto_kick!(name)
    end

    def add_player_report(name, reporter, reason)
    end

    def log(message)
      Kernel.log("PLUGIN: #{@___name}", message)
    end

    def database(sql)
      Database.transaction do
        Database.execute(sql)
      end
    end
  end
end
