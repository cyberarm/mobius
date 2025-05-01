module Mobius
  class PlayerData
    class Player
      DEFAULT_SKILL = 0.0

      attr_reader :origin, :data
      attr_accessor :id, :name, :join_time, :score, :team, :ping, :address, :kbps, :rank, :kills, :deaths, :money, :kd, :time, :last_updated

      def initialize(origin:, id:, name:, join_time:, score:, team:, ping:, address:, kbps:, rank:, kills:, deaths:, money:, kd:, time:, last_updated:)
        # Connection method
        @origin = origin

        @id           = id # String
        @name         = name # String
        @join_time    = join_time # Float | Monotonic Time
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
        @time         = time # Float | Monotonic Time
        @last_updated = last_updated # Float | Monotonic Time

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
        set_value(key, value) unless @data[key]
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

        # MISC.
        @time = 0 # reset 'play time' for stats reasons
        @last_updated = monotonic_time

        @data.delete(:manual_team)
      end

      def remote_moderation?
        @origin == :mobius_moderation_tool
      end

      def discord?
        @origin == :discord
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

        # FIXME: Use a a "shadow" PlayerData object to store active match data so that a disconnect doesn't purge players stats...
      def update_rank_data(win_data, tally)
        model = Database::Rank.first(name: @name.downcase) || Database::Rank.create(name: @name.downcase, skill: DEFAULT_SKILL)

        # NOTE: This will fail here if teams.json is not setup correctly
        winning_team = Teams.id_from_name(win_data[:winning_team_name])[:id]
        on_winning_team = @team == winning_team
        round_rating = 0.0

        tally_total_damage = tally.data[:stats_damage] + tally.data[:stats_building_damage] + tally.data[:stats_vehicle_damage]
        tally_total_repairs = tally.data[:stats_healed] + tally.data[:stats_building_repairs] + tally.data[:stats_vehicle_repairs]

        player_total_damage = @data[:stats_damage] + @data[:stats_building_damage] + @data[:stats_vehicle_damage]
        player_total_repairs = @data[:stats_healed] + @data[:stats_building_repairs] + @data[:stats_vehicle_repairs]

        ##########################################################
        # Round is not worth consideration for SKILL adjustment. #
        ##########################################################
        if tally_total_damage > 100 && tally_total_repairs > 25
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
        end

        skill = model.skill
        skill += round_rating
        skill = 0.0 if skill < 0
        skill = 100.0 if skill > 100.0

        model.update(
          skill: skill,
          stats_total_matches: model.stats_total_matches + 1,
          stats_matches_won: model.stats_matches_won + (on_winning_team ? 1 : 0),
          stats_matches_lost: model.stats_matches_lost + (!on_winning_team ? 1 : 0),
          stats_score: model.stats_score + @data[:stats_score],
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
          stats_vehicles_stolen: model.stats_vehicles_stolen + @data[:stats_vehicles_stolen],
          stats_total_time: model.stats_total_time + @data[:stats_match_time]
        )
      end
    end

    @player_data = {}
    @match_stats = {}

    def self.update(origin:, id:, name:, score:, team:, ping:, address:, kbps:, rank:, kills:, deaths:, money:, kd:, last_updated:)
      if (player = @player_data[id])
        player_updated = player.score != score ||
                         player.team != team ||
                         player.ping != ping ||
                         player.kbps != kbps ||
                         player.rank != rank ||
                         player.kills != kills ||
                         player.deaths != deaths ||
                         player.money != money ||
                         player.kd != kd
                         # Time is not a useful metric

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

        if player_updated
          PlayerData.update_match_stats(player)

          PluginManager.publish_event(
            :player_updated,
            player
          )
        end
      else
        # TODO: Check bans, kicks, etc.
        # FIXME: Not that we have the technology, actually do this now!

        @player_data[id] = Player.new(
          origin: origin,
          id: id,
          name: name,
          join_time: monotonic_time,
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

        Database::Rank.first(name: name.downcase) || Database::Rank.create(name: name.downcase, skill: Player::DEFAULT_SKILL)

        log "PlayerData", "#{player.name} has joined the game"

        PlayerData.update_match_stats(player)
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

    # Sync player stats to Player object that survives disconnects/rejoins
    def self.update_match_stats(player)
      stats_player = @match_stats[player.name]

      if stats_player
        player.data.each do |key, value|
          stats_player.set_value(key, value)
        end

        time_diff = monotonic_time - stats_player.value(:_last_stats_sync_update_time)
        stats_player.set_value(:stats_score, player.score)
        stats_player.increment_value(:stats_match_time, time_diff)
        stats_player.set_value(:_last_stats_sync_update_time, monotonic_time)
      else
        stats_player = @match_stats[player.name] = player.clone # Clone that their player (don't mutate actual player data)
        stats_player.set_value(:_last_stats_sync_update_time, monotonic_time)
      end
    end

    def self.match_stats
      @match_stats.map { |name, player| player }
    end

    def self.clear_match_stats
      @match_stats.clear
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

    def self.player(player_id_or_name, exact_match: true)
      if player_id_or_name.is_a?(Numeric)
        @player_data[player_id_or_name]
      else
        id = name_to_id(player_id_or_name, exact_match: exact_match)
        id >= 0 ? @player_data[id] : nil
      end
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
