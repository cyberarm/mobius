module Mobius
  class PlayerData
    class Player
      DEFAULT_ELO = 25.0

      attr_reader :origin, :data
      attr_accessor :id, :name, :join_time, :score, :team, :ping, :address, :kbps, :rank, :kills, :deaths, :money, :kd, :time, :last_updated

      def initialize(origin:, id:, name:, join_time:, score:, team:, ping:, address:, kbps:, rank:, kills:, deaths:, money:, kd:, time:, last_updated:)
        # Connection method
        @origin = origin

        @id           = id # String
        @name         = name # String
        @join_time    = join_time # Time
        @score        = score # Integer
        @team         = team # Integer
        @ping         = ping # Integer
        @address      = address # String
        @rank         =  rank # Integer
        @kills        =  kills # Integer
        @deaths       =  deaths # Integer
        @money        =  money # Integer
        @kd           =  kd # Float
        @kbps         = kbps # Integer
        @time         = time # Time
        @last_updated = last_updated # Time

        @data = { banned: false } # Hash
        reset
      end

      def value(key)
        @data[key]
      end

      def set_value(key, value)
        @data[key] = value
      end

      def increment_value(key, value = 1)
        @data[key] += value if @data[key]
      end

      def delete_value(key)
        @data.delete(key)
      end

      def banned?
        @data[:banned]
      end

      def reset
        # INFANTRY
        @data[:stats_kills] = 0
        @data[:stats_deaths] = 0
        @data[:stats_damage] = 0.0
        @data[:stats_healed] = 0.0

        # BUILDINGS
        @data[:stats_buildings_destroyed] = 0
        @data[:stats_building_repairs] = 0.0
        @data[:stats_building_damage] = 0.0 # damage dealt _to_ building

        # VEHICLES
        @data[:stats_vehicles_lost] = 0
        @data[:stats_vehicles_destroyed] = 0
        @data[:stats_vehicle_repairs] = 0.0
        @data[:stats_vehicle_damage] = 0.0 # damage dealt _to_ vehicle
        @data[:stats_vehicles_captured] = 0
        @data[:stats_vehicles_stolen] = 0

        @data.delete(:manual_team)
      end

      def remote_moderation?
        @origin == :mobius_moderation_tool
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

      def change_team(team, kill: true)
        old_team = @team

        @team = team
        RenRem.cmd("#{kill ? 'team2' : 'team3'} #{@id} #{@team}")
        RenRem.enqueue("pinfo")

        PlayerData.process_team_change(id, old_team, @team) if old_team != @team
      end

      def update_rank_data(win_data, tally)
        model = Database::Rank.first(name: @name.downcase) || Database::Rank.create(name: @name.downcase, elo: DEFAULT_ELO)

        winning_team = Teams.id_from_name(win_data[:winning_team_name])[:id]
        round_rating = 0.0

        tally_total_damage = tally.data[:stats_damage] + tally.data[:stats_building_damage] + tally.data[:stats_vehicle_damage]
        tally_total_repairs = tally.data[:stats_healed] + tally.data[:stats_building_repairs] + tally.data[:stats_vehicle_repairs]

        player_total_damage = @data[:stats_damage] + @data[:stats_building_damage] + @data[:stats_vehicle_damage]
        player_total_repairs = @data[:stats_healed] + @data[:stats_building_repairs] + @data[:stats_vehicle_repairs]

        # Round is not worth consideration.
        return if tally_total_damage <= 100
        return if tally_total_repairs <= 25

        excellent = 1.0
        okay      = 0.5
        bad       = excellent * -2.0

        if player_total_damage >= tally_total_damage * 0.08
          round_rating += excellent
        elsif player_total_damage >= tally_total_damage * 0.03
          round_rating += okay
        elsif player_total_damage <= tally_total_damage * 0.01
          round_rating += bad
        end

        if player_total_repairs >= tally_total_repairs * 0.10
          round_rating += excellent
        elsif player_total_repairs >= tally_total_repairs * 0.05
          round_rating += okay
        elsif player_total_repairs <= tally_total_repairs * 0.01
          round_rating += bad
        end

        elo = model.elo
        elo += round_rating
        elo = 0.0 if elo < 0
        elo = 100.0 if elo > 100.0

        model.update(
          elo: elo,
          stats_total_matches: model.stats_total_matches + 1,
          stats_matches_won: model.stats_matches_won + (winning_team ? 1 : 0),
          stats_matches_lost: model.stats_matches_lost + (!winning_team ? 1 : 0),
          stats_score: model.stats_score + @score,
          stats_kills: model.stats_kills + @data[:stats_kills],
          stats_deaths: model.stats_deaths + @data[:stats_deaths],
          stats_damage: model.stats_damage + @data[:stats_damage],
          stats_healed: model.stats_healed + @data[:stats_healed],
          stats_buildings_destroyed: model.stats_buildings_destroyed + @data[:stats_buildings_destroyed],
          stats_building_repairs: model.stats_building_repairs + @data[:stats_building_repairs],
          stats_building_damage: model.stats_building_damage + @data[:stats_building_damage],
          stats_vehicles_lost: model.stats_vehicles_lost + @data[:stats_vehicles_lost],
          stats_vehicles_destroyed: model.stats_vehicles_destroyed + @data[:stats_vehicles_destroyed],
          stats_vehicle_repairs: model.stats_vehicle_repairs + @data[:stats_vehicle_repairs],
          stats_vehicle_damage: model.stats_vehicle_damage + @data[:stats_vehicle_damage],
          stats_vehicles_captured: model.stats_vehicles_captured + @data[:stats_vehicles_captured],
          stats_vehicles_stolen: model.stats_vehicles_stolen + @data[:stats_vehicles_stolen]
        )
      end
    end

    @player_data = {}

    def self.update(origin:, id:, name:, score:, team:, ping:, address:, kbps:, rank:, kills:, deaths:, money:, kd:, last_updated:)
      if (player = @player_data[id])
        old_team = player.team

        player.score = score
        player.team = team
        player.ping = ping
        player.kbps = kbps
        player.rank = rank
        player.kills = kills
        player.deaths = deaths
        player.money = money
        player.kd = kd
        player.time += last_updated - player.last_updated
        player.last_updated = last_updated

        if old_team != team
          process_team_change(id, old_team, team)
        end
      else
        # TODO: Check bans, kicks, etc.
        # FIXME: Not that we have the technology, actually do this now!

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
          rank: rank,
          kills: kills,
          deaths: deaths,
          money: money,
          kd: kd,
          time: 0,
          last_updated: last_updated
        )

        player = @player_data[id]

        # Only create IP record for new name/ip combos
        unless (known_ip = Database::IP.first(name: name.downcase, ip: address.split(";").first))
          Database::IP.create(name: name.downcase, ip: address.split(";").first)
        end

        Database::Rank.first(name: name.downcase) || Database::Rank.create(name: name.downcase, elo: Player::DEFAULT_ELO)

        log "PlayerData", "#{player.name} has joined the game"

        PluginManager.publish_event(
          :player_joined,
          player
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
      return -1 if name.to_s.empty?

      if exact_match
        player = player_list.find { |ply| ply.name.downcase == name&.downcase }
        player ? player.id : -1
      else
        name_exact_match = player_list.find { |ply| ply.name.downcase == name&.downcase }

        return name_exact_match.id if name_exact_match

        players = player_list.select { |ply| ply.name.downcase.include?(name&.downcase) }
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
