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
      @current_players = {}

      @ready = true
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
        position(line)
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
      object[:x]      = data[5].to_f
      object[:y]      = data[6].to_f
      object[:z]      = data[7].to_f
      object[:facing] = data[8].to_f
      object[:health] = data[9].to_f
      object[:armor]  = data[10].to_f
      object[:team]   = data[11].to_i

      pp object
    end

    def created(line)
      data = line.split(";")
      object = {}

      object[:type]       = data[1]
      object[:object]     = data[2]
      object[:preset]     = data[3]
      object[:x]          = data[4].to_f
      object[:y]          = data[5].to_f
      object[:z]          = data[6].to_f
      object[:facing]     = data[7].to_f
      object[:max_health] = data[8].to_f
      object[:health]     = data[8].to_f
      object[:max_armor]  = data[9].to_f
      object[:armor]      = data[9].to_f
      object[:team]       = data[10].to_i
      object[:name]       = data[11]
      object[:destroyed]  = 0
      object[:killed]     = 0
      object[:drivers]    = 0

      @game_objects[object[:object]] = object

      case object[:type].downcase
      when "vehicle"
        if @vehicle_from_crate && @vehicle_from_crate == object[:preset]
          object[:last_team] = 2
        else
          object[:last_team] = object[:team]
        end
      when "soldier"
        @current_players[object[:name].downcase] = object[:object]
      end

      # FIXME: Emit event to plugins

      pp object
    end

    def destroyed(line)
      data = line.split(";")
      object = {}

      object[:type]   = data[1]
      object[:object] = data[2]
      object[:preset] = data[3]
      object[:x]      = data[4].to_f
      object[:y]      = data[5].to_f
      object[:z]      = data[6].to_f
      object[:health] = data[7].to_f

      case object[:type].downcase
      when "soldier"
        @current_players.delete(@current_players.find { |name, obj| obj == object[:object] } )
      end

      if @game_objects[object[:object]]
        @game_objects[object[:object]][:destroyed] = true
      end

      pp object
    end

    def position(line)
      data = line.split(";")
      object = {}

      object[:type]       = data[1]
      object[:object]     = data[2]
      object[:preset]     = data[3]
      object[:x]          = data[4].to_f
      object[:y]          = data[5].to_f
      object[:z]          = data[6].to_f
      object[:facing]     = data[7].to_f
      object[:max_health] = data[8].to_f # ???
      object[:health]     = data[8].to_f
      object[:armor]      = data[9].to_f

      if (obj = @game_objects[object[:object]])
        obj[:health] = object[:health]
        obj[:armor] = object[:armor]
        obj[:x] = object[:x]
        obj[:y] = object[:y]
        obj[:z] = object[:z]
        obj[:facing] = object[:facing]
      end

      pp object
    end

    def enter_vehicle(line)
      data = line.split(";")
      object = {}

      object[:vehicle_object] = data[1]
      object[:vehicle_preset] = data[2]
      object[:vehicle_x]      = data[3].to_f
      object[:vehicle_y]      = data[4].to_f
      object[:vehicle_z]      = data[5].to_f

      object[:player_object]  = data[6]
      object[:player_preset]  = data[7]
      object[:player_x]       = data[8].to_f
      object[:player_y]       = data[9].to_f
      object[:player_z]       = data[10].to_f

      if (player_obj = @game_objects[object[:player_object]] && vehicle_obj = @game_objects[object[:vehicle_object]])
        player_obj[:vehicle] = object[:vehicle_object]
        vehicle_obj[:drivers] += 1

        if vehicle_obj[:drivers] == 1
          vehicle_obj[:driver] = object[:player_object]
          vehicle_obj[:last_driver] = object[:player_object]
          vehicle_obj[:team] = player_obj[:team]

          # Vehicle has been stolen
          if vehicle_obj[:last_team] != player_obj[:team]
            if vehicle_obj[:last_team] != 2
              vehicle_name = translate_preset(vehicle_obj[:preset])

              # FIXME: Add a mobius annnouncement method to simplify these sorts of broadcasts
              RenRem.cmd("msg [MOBIUS] #{player_obj[:name]} has stolen a #{vehicle_name}!")
            end

            vehicle_obj[:last_team] = player_obj[:team]
          end
        end
      end

      pp object
    end

    def exit_vehicle(line)
      data = line.split(";")
      object = {}

      object[:vehicle_object] = data[1]
      object[:vehicle_preset] = data[2]
      object[:vehicle_x]      = data[3].to_f
      object[:vehicle_y]      = data[4].to_f
      object[:vehicle_z]      = data[5].to_f

      object[:player_object]  = data[6]
      object[:player_preset]  = data[7]
      object[:player_x]       = data[8].to_f
      object[:player_y]       = data[9].to_f
      object[:player_z]       = data[10].to_f

      if (player_obj = @game_objects[object[:player_object]] && vehicle_obj = @game_objects[object[:vehicle_object]])
        player_obj[:vehicle] = nil
        vehicle_obj[:drivers] -= 1

        if vehicle_obj[:drivers].zero?
          vehicle_obj[:driver] = nil
          vehicle_obj[:team] = -1 # Neutral Team
        end
      end

      pp object
    end

    def damaged(line)
      data = line.split(";")
      object = {}

      object[:type]      = data[1]
      object[:object]    = data[2]
      object[:preset]    = data[3]
      object[:x]         = data[4].to_f
      object[:y]         = data[5].to_f
      object[:z]         = data[6].to_f
      object[:facing]    = data[7].to_f

      object[:damager_object] = data[8]
      object[:damager_preset] = data[9]
      object[:damager_x]      = data[10].to_f
      object[:damager_y]      = data[11].to_f
      object[:damager_z]      = data[12].to_f
      object[:damager_facing] = data[13].to_f

      object[:damage] = data[14].to_f
      object[:health] = data[15].to_f
      object[:armor]  = data[16].to_f

      # Setting new health and armor of the object.
      obj = @game_objects[object[:object]]
      if (obj)
        obj[:health] = object[:health]
        obj[:armor] = object[:armor]
      end

      # If the damage is less than 0 it's actually being repaired
      if (damager = @game_objects[object[:damager_object]]) && object[:damage].negative? && (player = PlayerData.player(PlayerData.name_to_id(damager[:name])))
        case object[:type].downcase.strip
        when "building"
          player.increment_value(:stats_building_repair, -object[:damage])
        when "vehicle"
          player.increment_value(:stats_vehicle_repair, -object[:damage]) if obj[:drivers].positive?
        end
      end

      pp object
    end

    def killed(line)
      data = line.split(";")
      object = {}

      object[:killed_type]      = data[1]
      object[:killed_object]    = data[2]
      object[:killed_preset]    = data[3]
      object[:killed_x]         = data[4].to_f
      object[:killed_y]         = data[5].to_f
      object[:killed_z]         = data[6].to_f
      object[:killed_direction] = data[7].to_f # facing?

      object[:killer_object]    = data[8]
      object[:killer_preset]    = data[9]
      object[:killer_x]         = data[10].to_f
      object[:killer_y]         = data[11].to_f
      object[:killer_z]         = data[12].to_f
      object[:killer_direction] = data[13].to_f # facing?
      object[:killer_weapon]    = data[14]

      if (killed_obj = @game_objects[object[:killed_object]]) && (killer_obj = @game_objects[object[:killer_object]])

      end

      pp object
    end

    # PURCHASED;CHARACTER;cyberarm;Soviet_Technician;Technician
    def purchased(line)
      data = line.split(";")
      object = {}

      # TODO: validate these keys
      object[:type]   = data[1]
      object[:object] = data[2] # player name
      object[:preset] = data[3]
      object[:name]   = data[4]

      player_team = @game_objects[@current_players[object[:object]]][:team]

      case object[:type].downcase
      when "vehicle"
        RenRem.cmd("cmsgt #{player_team} 255,127,0 [MOBIUS] #{object[:object]} purchased a #{object[:name]}!")
      end

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

      clear_data
    end

    def config(line)
      # TODO: RESET DATA FOR NEXT GAME

      clear_data
    end

    def clear_data
      @game_objects.clear
      @current_players.clear

      PlayerData.player_list.each(&:reset)

      @last_purchase_team_one = nil
      @last_purchase_team_two = nil
    end
  end
end
