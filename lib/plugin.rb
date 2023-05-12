module Mobius
  class Plugin
    Timer = Struct.new(:type, :ticks, :delay, :block)
    Command = Struct.new(:plugin, :name, :aliases, :arguments, :help, :groups, :block)

    attr_reader :___name, :___database_name, :___version, :___event_handlers, :___timers, :___data, :___plugin_file

    # RESERVED
    def self.__remix_teams_first_pick
      @__remix_teams_first_pick ||= 0
    end

    # RESERVED
    def self.__remix_teams_first_pick=(n)
      @__remix_teams_first_pick = n
    end

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

    def every(seconds, &block)
      @___timers << Timer.new(:every, 0, seconds, block)
    end

    def after(seconds, &block)
      @___timers << Timer.new(:after, 0, seconds, block)
    end

    def broadcast_message(message, red: 255, green: 255, blue: 255)
      renrem_cmd("cmsg #{red},#{green},#{blue} #{message}")
    end

    def message_team(team_id, message, red: 255, green: 255, blue: 255)
      renrem_cmd("cmsgt #{team_id} #{red},#{green},#{blue} #{message}")
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
      PlayerData.player_list.each do |player|
        page_player(player.name, message) if player.administrator? || player.moderator?
      end
    end

    def auto_kick!(name)
    end

    def add_player_report(name, reporter, reason)
    end

    def remix_teams
      return unless ServerStatus.total_players.positive?

      team_zero = []
      team_one = []
      list = []

      PlayerData.player_list.select(&:ingame?).each do |player|
        rating = Database::Rank.first(name: player.name.downcase)&.skill || 0.0

        list << [player, rating]
      end

      list.sort_by! { |l| [l[1], l[0].name.downcase] }.reverse

      list.each do |player, _rating|
        (Plugin.__remix_teams_first_pick.zero? ? team_zero : team_one) << player
        Plugin.__remix_teams_first_pick = Plugin.__remix_teams_first_pick.zero? ? 1 : 0
      end

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
  end
end
