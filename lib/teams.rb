module Mobius
  class Teams
    SPECTATOR = -4
    MUTANT = -3
    NEUTRAL = -2
    RENEGADE = -1
    UNTEAMED = -1
    NOD = 0
    TEAM_ZERO = 0
    GDI = 1
    TEAM_ONE = 1
    TEAM_DONOTUSE = 2 # some scripts do special things with Team 2
    TEAM_THREE = 3
    TEAM_FOUR = 4
    TEAM_FIVE = 5
    TEAM_SIX = 6
    TEAM_SEVEN = 7
    TEAM_EIGHT = 8

    @teams = [
      {
        id: 0,
        name: "Nod",
        abbreviation: "Nod",
        color: "bf1b26"
      },
      {
        id: 1,
        name: "GDI",
        abbreviation: "GDI",
        color: "ffb500"
      },
      {
        id: 2,
        name: "Neutral",
        abbreviation: "Neu",
        color: "ffffff"
      }
    ]

    @team_first_picking = 0

    def self.init
      log "INIT", "Loading Teams..."

      read_config
    end

    def self.teardown
    end

    def self.read_config(path: "#{ROOT_PATH}/conf/teams.json")
      raise "Teams config file not found at: #{path}" unless File.exist?(path)

      json = File.read(path)

      begin
        result = config_valid?(JSON.parse(json, symbolize_names: true))
        @teams = result if result
      # FIXME: Find the correct name for this exception
      rescue JSONParserException => e
        pp e
        abort "Failed to parse #{path}"
      end
    end

    def self.config_valid?(array)
      return false unless array.is_a?(Array)

      array
    end

    def self.id_from_name(team)
      return team if team.is_a?(Integer)

      @teams.find { |hash| hash[:name].downcase == team.to_s.downcase || hash[:abbreviation].downcase == team.to_s.downcase }
    end

    def self.name(team)
      hash = nil
      hash = id_from_name(team) if team.is_a?(String)
      hash = @teams.find { |h| h[:id] == team } if team.is_a?(Integer)

      if hash
        hash[:name]
      else
        "Unknown"
      end
    end

    def self.abbreviation(team)
      hash = nil
      hash = id_from_name(team) if team.is_a?(String)
      hash = @teams.find { |h| h[:id] == team } if team.is_a?(Integer)

      if hash
        hash[:abbreviation]
      else
        "Unk"
      end
    end

    def self.team(team)
      id = id_from_name(team)

      @teams.find { |h| h[:id] == id }
    end

    def self.color(team)
      hash = team(team)

      if hash
        hash[:color] || hash[:colour]
      else
        Color::IRC_COLORS[00] # White
      end
    end

    def self.rgb_color(team)
      color = color(team)

      return Color.new(red: 255, green: 255, blue: 255) unless color.length == 6

      hex_color = color.to_i(16)

      return Color.new(hex_color)
    end

    def self.list
      @teams
    end

    def self.colorize(team, message)
      Color.irc_colorize(rgb_color(team), message)
    end

    def self.colorize_name(team)
      Color.irc_colorize(rgb_color(team), name(team))
    end

    def self.colorize_abbreviation(team)
      Color.irc_colorize(rgb_color(team), abbreviation(team))
    end

    def self.skill_sort_teams
      team_zero = []
      team_one = []
      team_zero_rating = 0.0
      team_one_rating = 0.0
      list = []
      team_picking = @team_first_picking

      PlayerData.player_list.select(&:ingame?).each do |player|
        rank = Database::Rank.first(name: player.name.downcase)
        rating = 0.0

        if rank && rank.stats_total_matches >= 10
          win_ratio = rank.stats_matches_won / rank.stats_total_matches
          rating = (rank.stats_score / rank.stats_total_matches) * win_ratio
        end

        list << [player, rating]
      end

      list.sort_by! { |l| [l[1], l[0].name.downcase] }.reverse

      list.each do |player, rating|
        (team_picking.zero? ? team_zero : team_one) << player
        team_zero_rating += rating if team_picking.zero?
        team_one_rating += rating unless team_picking.zero?

        team_picking = team_picking.zero? ? 1 : 0
      end

      [team_zero, team_one, team_zero_rating, team_one_rating]
    end

    def self.team_first_picking
      @team_first_picking
    end

    def self.team_first_picking=(n)
      @team_first_picking = n
    end
  end
end
