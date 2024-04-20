module Mobius
  # use `extend Common` for adding methods as class methods
  # use `include Common` for adding methods as instance methods
  module Common
    def renrem_cmd(data, delay = nil)
      RenRem.cmd(data, delay)
    end

    def broadcast_message(message, red: 255, green: 255, blue: 255)
      renrem_cmd("cmsg #{red},#{green},#{blue} #{message}")
      PluginManager.publish_event(:irc_broadcast, message, red, green, blue)
    end

    def message_team(team_id, message, red: 255, green: 255, blue: 255)
      renrem_cmd("cmsgt #{team_id} #{red},#{green},#{blue} #{message}")
      PluginManager.publish_event(:irc_team_message, team_id, message, red, green, blue)
    end

    def message_player(player, message, red: 255, green: 255, blue: 255)
      if player.ingame?
        renrem_cmd("cmsgp #{player.id} #{red},#{green},#{blue} #{message}")
      elsif player.irc?
        if player.value(:_irc_channel)
          PluginManager.publish_event(:irc_admin_message, message, red, green, blue)
        else
          PluginManager.publish_event(:irc_pm, player, message, red, green, blue)
        end
      end
    end

    def page_player(player, message, red: 255, green: 255, blue: 255)
      if player.ingame?
        renrem_cmd("ppage #{player.id} #{message}")
      elsif player.irc?
        if player.value(:_irc_channel)
          PluginManager.publish_event(:irc_admin_message, message, red, green, blue)
        else
          PluginManager.publish_event(:irc_pm, player, message, red, green, blue)
        end
      end
    end
  end
end
