class Mobius
  class Teams
    def initialize
      @teams = [
        {
          id: 0,
          name: "Nod",
          abbreviation: "Nod",
          color: "04"
        },
        {
          id: 1,
          name: "GDI",
          abbreviation: "GDI",
          color: "08,15"
        },
        {
          id: 2,
          name: "Neutral",
          abbreviation: "Neu",
          color: "09"
        }
      ]

      read_config
    end

    def read_config
      path = "#{ROOT_PATH}/conf/teams.json"

      return unless File.exist?(path)

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

    def config_valid?(array)
      return false unless array.is_a?(Array)

      array
    end

    def id_from_name(team)
      return team if team.is_a?(Integer)

      @teams.find { |hash| hash[:name] == team || hash[:abbreviation] == team }
    end

    def name(team)
      hash = id_from_name(team)

      if hash
        hash[:name]
      else
        "Unknown"
      end
    end

    def abbreviation(team)
      hash = id_from_name(team)

      if hash
        hash[:abbreviation]
      else
        "Unk"
      end
    end

    def color(team)
      hash = id_from_name(team)

      if hash
        hash[:color] || hash[:colour]
      else
        "01"
      end
    end

    def colorize_name(team)
      IRC.colorize(color(team), name(team))
    end

    def colorize_abbreviation(team)
      IRC.colorize(color(team), abbreviation(team))
    end
  end
end
