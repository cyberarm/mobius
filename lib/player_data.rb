class Mobius
  class PlayerData

    attr_reader :origin
    attr_accessor :id, :name, :join_time, :score, :team, :ping, :ip, :kbps, :time, :last_updated

    class Player
      def initialize(origin:, id:, name:, join_time:, score:, team:, ping:, ip:, kbps:, time:, last_updated:)
        # Connection method
        @origin = origin

        @id           = id # String
        @name         = name # String
        @join_time    = join_time # Time
        @score        = score # Integer
        @team         = team # Integer
        @ping         = ping # Integer
        @ip           = ip # String
        @kbps         = kbps # Integer
        @time         = time # Time
        @last_updated = last_updated # Time

        @data = {} # Hash
      end

      def value(key)
        @data[key]
      end

      def set_value(key, value)
        @data[key] = value
      end

      def increment_value(key, value)
        @data[key] += value if @data[key]
      end

      def delete_value(key)
        @data[key]
      end

      def remote_moderation?
        @origin == :w3d_server_moderation_tool
      end

      def irc?
        @origin == :irc
      end

      def ingame?
        @origin == :game
      end

      def admin?
        false
      end

      def mod?
        false
      end

      def temp_mod?
        false
      end
    end

    def initialize
      @player_data = {}
    end

    def delete(player)
      @player_data.delete(player.id)
    end

    def clear
      @player_data.clear
    end

    def name_to_id(playername, exact_match)
      raise NotImplementedError
    end

    def player(player_id, exact_match)
      raise NotImplementedError
    end

    def player_list
      @player_data.map { |_, value| value }
    end

    def players_by_team(team)
      if team.is_a?(Integer)
        player_list.select { |ply| ply.team == team }
      elsif team.is_a?(String)
        raise NotImplementedError
      else
        # caller.__warn("PlayerData#players_by_team invalid argument for team, expected an Integer or a String, got #{team.class}")
        nil
      end
    end

    def process_team_change(player, old_team, new_team)
      PluginManager.publish_event(:team_changed, player, old_team, new_team)
    end
  end
end
