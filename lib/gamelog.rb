module Mobius
  class GameLog
    @@instance = nil

    def self.init
      log("INIT", "Enabling GameLog...")
      new
    end

    def self.teardown
      log("TEARDOWN", "Shutdown GameLog...")
    end

    def self.feed(line)
      @@instance&.parse_line(line)
    end

    def initialize
      @@instance = self

      @clients = []
      @gamelog_running = nil
      @gamelog_name = nil

      @wreckages = {}
      @vehicles = {}
      @presets = {}
      @weapons = {}

      @area_data = nil

      @game_objects = {}

      @ready = true
      @current_players = 0
      @last_purchase_team_one = nil # NOD, Soviets
      @last_purchase_team_two = nil # GDI, Allies
      @vehicle_from_create = nil
    end

    def parse_line(line)
      return unless @ready

      case line
      when /\[(.+?)\] CRATE/
        log("GameLog", "CRATE")
        crate(line)
      when /\[(.+?)\] CREATED/
        log("GameLog", "CREATED")
        created(line)
      when /\[(.+?)\] DESTROYED/
        log("GameLog", "DESTROYED")
        destroyed(line)
      when /\[(.+?)\] POS/
        log("GameLog", "POS")
        pos(line)
      when /\[(.+?)\] ENTER/
        log("GameLog", "ENTER")
        enter_vehicle(line)
      when /\[(.+?)\] EXIT/
        log("GameLog", "EXIT") # exit is a reserved keyword
        exit_vehicle(line)
      when /\[(.+?)\] DAMAGED/
        log("GameLog", "DAMAGED")
        damaged(line)
      when /\[(.+?)\] KILLED/
        log("GameLog", "KILLED")
        killed(line)
      when /\[(.+?)\] PURCHASED/
        log("GameLog", "PURCHASED")
        purchased(line)
      when /\[(.+?)\] SCORE/
        log("GameLog", "SCORE")
        score(line)
      when /\[(.+?)\] WIN/
        log("GameLog", "WIN")
        win(line)
      when /\[(.+?)\] CONFIG/
        log("GameLog", "CONFIG")
        config(line)
      else
        log("GameLog", "UNHANDLED LINE: #{line}")
      end
    end

    def crate(line)
      data = line.split(";")
      object = {}

      object[:type]   = data[1]
      object[:param]  = data[2]
      object[:object] = data[3]
      object[:preset] = data[4]
      object[:x]      = data[5]
      object[:y]      = data[6]
      object[:z]      = data[7]
      object[:facing] = data[8]
      object[:health] = data[9]
      object[:armor]  = data[10]
      object[:team]   = data[11]

      pp object
    end

    def created(line)
      data = line.split(";")
      object = {}

      object[:type]       = data[1]
      object[:object]     = data[2]
      object[:preset]     = data[3]
      object[:x]          = data[4]
      object[:y]          = data[5]
      object[:z]          = data[6]
      object[:facing]     = data[7]
      object[:max_health] = data[8]
      object[:health]     = data[8]
      object[:max_armor]  = data[9]
      object[:armor]      = data[9]
      object[:team]       = data[10]
      object[:name]       = data[11]
      object[:destroyed]  = 0
      object[:killed]     = 0
      object[:drivers]    = 0

      pp object
    end

    def destroyed(line)
      data = line.split(";")
      object = {}

      object[:type]   = data[1]
      object[:object] = data[2]
      object[:preset] = data[3]
      object[:x]      = data[4]
      object[:y]      = data[5]
      object[:z]      = data[6]
      object[:health] = data[7]

      pp object
    end

    def pos(line)
      data = line.split(";")
      object = {}

      object[:type]       = data[1]
      object[:object]     = data[2]
      object[:preset]     = data[3]
      object[:x]          = data[4]
      object[:y]          = data[5]
      object[:z]          = data[6]
      object[:facing]     = data[7]
      object[:max_health] = data[8] # ???
      object[:health]     = data[8]
      object[:armor]      = data[9]

      pp object
    end

    def enter_vehicle(line)
      data = line.split(";")
      object = {}

      object[:vehicle_object] = data[1]
      object[:vehicle_preset] = data[2]
      object[:vehicle_x]      = data[3]
      object[:vehicle_y]      = data[4]
      object[:vehicle_z]      = data[5]
      object[:player_object]  = data[6]
      object[:player_preset]  = data[7]
      object[:player_x]       = data[8]
      object[:player_y]       = data[9]
      object[:player_z]       = data[10]

      pp object
    end

    def exit_vehicle(line)
      data = line.split(";")
      object = {}

      object[:vehicle_object] = data[1]
      object[:vehicle_preset] = data[2]
      object[:vehicle_x]      = data[3]
      object[:vehicle_y]      = data[4]
      object[:vehicle_z]      = data[5]
      object[:player_object]  = data[6]
      object[:player_preset]  = data[7]
      object[:player_x]       = data[8]
      object[:player_y]       = data[9]
      object[:player_z]       = data[10]

      pp object
    end

    def damaged(line)
      data = line.split(";")
      object = {}

      object[:type]      = data[1]
      object[:object]    = data[2]
      object[:preset]    = data[3]
      object[:x]         = data[4]
      object[:y]         = data[5]
      object[:z]         = data[6]
      object[:facing]    = data[7]

      object[:damager_object] = data[8]
      object[:damager_preset] = data[9]
      object[:damager_x]      = data[10]
      object[:damager_y]      = data[11]
      object[:damager_z]      = data[12]
      object[:damager_facing] = data[13]
      object[:damager_damage] = data[14]
      object[:damager_health] = data[15]
      object[:damager_armor]  = data[16]

      pp object
    end

    def killed(line)
      data = line.split(";")
      object = {}

      object[:killed_type]      = data[1]
      object[:killed_object]    = data[2]
      object[:killed_preset]    = data[3]
      object[:killed_x]         = data[4]
      object[:killed_y]         = data[5]
      object[:killed_z]         = data[6]
      object[:killed_direction] = data[7] # facing?

      object[:killer_object]    = data[8]
      object[:killer_preset]    = data[9]
      object[:killer_x]         = data[10]
      object[:killer_y]         = data[11]
      object[:killer_z]         = data[12]
      object[:killer_direction] = data[13] # facing?
      object[:killer_weapon]    = data[14]

      pp object
    end

    # PURCHASED;CHARACTER;cyberarm;Soviet_Technician;Technician
    def purchased(line)
      data = line.split(";")
      object = {}

      # TODO: validate these keys
      object[:type]   = data[1]
      object[:object] = data[2]
      object[:preset] = data[3]
      object[:name]   = data[4]

      pp object
    end

    # APB seems to be reporting player credits here: SCORE;1500000729;0;1648
    def score(line)
      data = line.split(";")
      object = {}

      # TODO: Validate thise keys
      object[:object]  = data[1]
      object[:score]   = data[2]
      object[:credits] = data[3]

      pp object
    end

    def win(line)
      # TODO: RESET DATA FOR NEXT GAME
    end

    def config(line)
      # TODO: RESET DATA FOR NEXT GAME
    end
  end
end
