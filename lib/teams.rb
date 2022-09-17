module Mobius
  class Teams
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

    def self.color(team)
      hash = id_from_name(team)

      if hash
        hash[:color] || hash[:colour]
      else
        "01"
      end
    end

    def self.list
      @teams
    end

    def self.colorize_name(team)
      IRC.colorize(color(team), name(team))
    end

    def self.colorize_abbreviation(team)
      IRC.colorize(color(team), abbreviation(team))
    end
  end
end
