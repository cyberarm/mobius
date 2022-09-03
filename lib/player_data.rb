module Mobius
  class PlayerData
    class Player
      attr_reader :origin
      attr_accessor :id, :name, :join_time, :score, :team, :ping, :address, :kbps, :time, :last_updated

      def initialize(origin:, id:, name:, join_time:, score:, team:, ping:, address:, kbps:, time:, last_updated:)
        # Connection method
        @origin = origin

        @id           = id # String
        @name         = name # String
        @join_time    = join_time # Time
        @score        = score # Integer
        @team         = team # Integer
        @ping         = ping # Integer
        @address      = address # String
        @kbps         = kbps # Integer
        @time         = time # Time
        @last_updated = last_updated # Time

        @data = { banned: false } # Hash
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
        @data.delete(key)
      end

      def banned?
        @data[:banned]
      end

      def reset
        @data.delete(:stats_kills)
        @data.delete(:stats_deaths)
        @data.delete(:stats_building_kills)
        @data.delete(:stats_building_kills_building_a) # ???
        @data.delete(:stats_building_repairs)
        @data.delete(:stats_vehicle_kills)
        @data.delete(:stats_vehicle_repairs)
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

      def administrator?
        @data[:administrator]
      end

      def moderator?
        @data[:moderator]
      end

      def director?
        @data[:director]
      end

      def in_group?(groups)
        return true if groups.include?(:admin) && administrator?
        return true if groups.include?(:mod) && moderator?
        return true if groups.include?(:director) && director?
        return true if groups.include?(:ingame) && ingame?
      end
    end

    @player_data = {}

    def self.update(origin:, id:, name:, score:, team:, ping:, address:, kbps:, time:, last_updated:)
      if (player = @player_data[id])
        if player.team != team
          process_team_change(id, player.team, team)
        end

        player.score = score
        player.team = team
        player.ping = ping
        player.kbps = kbps
        player.time = time
        player.last_updated = last_updated
      else
        # TODO: Check bans, kicks, etc.

        @player_data[id] = Player.new(
          origin: origin,
          id: id,
          name: name,
          join_time: Time.now.utc,
          score: score,
          team: team,
          ping: ping,
          address: address,
          kbps: kbps,
          time: time,
          last_updated: last_updated
        )
      end
    end

    def self.delete(player)
      # TODO: Check if player is a moderator

      @player_data.delete(player.id)
    end

    def self.clear
      @player_data.clear
    end

    def self.name_to_id(name, exact_match: true)
      if exact_match
        player = @player_data.find { |_, data| data.name.downcase == name&.downcase }&.last
        player ? player.id : -1
      else
        players = player_list.select { |ply| ply.name.downcase.start_with?(name&.downcase) }
        players.size == 1 ? players.first&.id : -1
      end
    end

    def self.player(player_id)
      @player_data[player_id]
    end

    def self.player_list
      @player_data.map { |_, value| value }
    end

    def self.players_by_team(team)
      if team.is_a?(Integer)
        player_list.select { |ply| ply.team == team }
      elsif team.is_a?(String)
        raise NotImplementedError
      else
        # caller.__warn("PlayerData#players_by_team invalid argument for team, expected an Integer or a String, got #{team.class}")
        nil
      end
    end

    def self.process_team_change(player, old_team, new_team)
      PluginManager.publish_event(:team_changed, player, old_team, new_team)
    end
  end
end
