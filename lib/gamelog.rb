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

    [:wreckages, :vehicles, :presets, :weapons, :area_data, :game_objects, :current_players,
                :last_purchase_team_one, :last_purchase_team_two, :vehicle_from_create].each do |item|
      GameLog.define_singleton_method(item) do
        @@instance.send(item)
      end
    end

    attr_reader :wreckages, :vehicles, :presets, :weapons, :area_data, :game_objects, :current_players,
                :last_purchase_team_one, :last_purchase_team_two, :vehicle_from_create

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

      if Config.record_gamelog
        FileUtils.mkdir_p("#{ROOT_PATH}/data")
        @data_recorder = File.open("#{ROOT_PATH}/data/gamelog_#{Time.now.strftime('%Y-%m-%d-%s')}.dat", "a+")

        at_exit do
          @data_recorder&.close
        end
      end
    end

    def parse_line(line)
      @data_recorder&.puts(line) if Config.record_gamelog

      return unless @ready

      case line
      when /\[(.+?)\] CRATE/
        log("GameLog", "CRATE") if Config.debug_verbose
        crate(line)
      when /\[(.+?)\] CREATED/
        log("GameLog", "CREATED") if Config.debug_verbose
        created(line)
      when /\[(.+?)\] DESTROYED/
        log("GameLog", "DESTROYED") if Config.debug_verbose
        destroyed(line)
      when /\[(.+?)\] POS/
        log("GameLog", "POS") if Config.debug_verbose
        position(line)
      when /\[(.+?)\] ENTER/
        log("GameLog", "ENTER") if Config.debug_verbose
        enter_vehicle(line)
      when /\[(.+?)\] EXIT/
        log("GameLog", "EXIT") if Config.debug_verbose # exit is a reserved keyword
        exit_vehicle(line)
      when /\[(.+?)\] DAMAGED/
        log("GameLog", "DAMAGED") if Config.debug_verbose
        damaged(line)
      when /\[(.+?)\] KILLED/
        log("GameLog", "KILLED") if Config.debug_verbose
        killed(line)
      when /\[(.+?)\] PURCHASED/
        log("GameLog", "PURCHASED") if Config.debug_verbose
        purchased(line)
      when /\[(.+?)\] SCORE/
        log("GameLog", "SCORE") if Config.debug_verbose
        score(line)
      when /\[(.+?)\] WIN/
        log("GameLog", "WIN") if Config.debug_verbose
        win(line)
      when /\[(.+?)\] 2.03/ # This is sadness
        log("GameLog", "MAPLOADED") if Config.debug_verbose
        maploaded(line)
      when /\[(.+?)\] CONFIG/
        log("GameLog", "CONFIG") if Config.debug_verbose
        config(line)
      when /\[(.+?)\] CHAT/
        log("GameLog", "CHAT") if Config.debug_verbose
        chat(line)
      else
        log("GameLog", "UNHANDLED LINE: #{line}") if Config.debug_verbose
      end

      PluginManager.publish_event(:gamelog, line)
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

      PluginManager.publish_event(:crate, object, data)

      pp object if Config.debug_verbose
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
      object[:destroyed]  = false
      object[:killed]     = false
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
      when "object"
        player_obj = @game_objects[object[:name]]
        object[:_player_object] = player_obj
      end

      PluginManager.publish_event(:created, object, data)

      pp object if Config.debug_verbose
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

      if @game_objects[object[:object]]
        @game_objects[object[:object]][:destroyed] = true
      end

      PluginManager.publish_event(:destroyed, object, data)

      case object[:type].downcase
      when "soldier"
        @current_players.delete(@current_players.find { |_name, obj| obj == object[:object] })
      when "vehicle"
        occupants = @current_players.select { |_name, obj| @game_objects[obj][:vehicle] == object[:object] }

        occupants.each { |o| o.delete(:vehicle) }
      end

      pp object if Config.debug_verbose
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

      PluginManager.publish_event(:position, object, data)

      pp object if Config.debug_verbose
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

      player_obj = @game_objects[object[:player_object]]
      vehicle_obj = @game_objects[object[:vehicle_object]]

      if player_obj && vehicle_obj
        player_obj[:vehicle] = object[:vehicle_object]
        vehicle_obj[:drivers] += 1

        last_driver = @game_objects[vehicle_obj[:last_driver]]

        if vehicle_obj[:drivers] == 1
          vehicle_obj[:driver] = object[:player_object]
          vehicle_obj[:last_driver] = object[:player_object]
          vehicle_obj[:team] = player_obj[:team]

          # Vehicle has been stolen
          if vehicle_obj[:last_team] != player_obj[:team]
            if vehicle_obj[:last_team] != 2
              vehicle_name = Presets.translate(vehicle_obj[:preset])

              # FIXME: Add a mobius annnouncement method to simplify these sorts of broadcasts
              if last_driver
                captured_by = PlayerData.player(PlayerData.name_to_id(player_obj[:name].to_s.downcase))
                stolen_from = PlayerData.player(PlayerData.name_to_id(last_driver[:name].to_s.downcase))

                captured_by&.increment_value(:stats_vehicles_captured)
                stolen_from&.increment_value(:stats_vehicles_stolen)

                RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{player_obj[:name]} has stolen #{last_driver[:name]}'s #{vehicle_name}!") if Config.messages[:vehicle_stolen]
              else
                RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{player_obj[:name]} has stolen a #{vehicle_name}!") if Config.messages[:vehicle_stolen]
              end
            end

            vehicle_obj[:last_team] = player_obj[:team]
          end
        end
      end

      object[:_player_object] = player_obj if player_obj
      object[:_vehicle_object] = vehicle_obj if vehicle_obj

      PluginManager.publish_event(:enter_vehicle, object, data)

      pp object if Config.debug_verbose
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

      player_obj = @game_objects[object[:player_object]]
      vehicle_obj = @game_objects[object[:vehicle_object]]

      if player_obj && vehicle_obj
        player_obj[:vehicle] = nil
        vehicle_obj[:drivers] -= 1

        if vehicle_obj[:drivers].zero?
          vehicle_obj[:driver] = nil
          vehicle_obj[:team] = -1 # Neutral Team
        end
      end

      object[:_player_object] = player_obj if player_obj
      object[:_vehicle_object] = vehicle_obj if vehicle_obj

      PluginManager.publish_event(:exit_vehicle, object, data)

      pp object if Config.debug_verbose
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

      if (damager = @game_objects[object[:damager_object]]) && (player = PlayerData.player(PlayerData.name_to_id(damager[:name])))
        # If the damage is less than 0 it's actually being repaired
        if object[:damage].negative?
          case object[:type].downcase.strip
          when "building"
            player.increment_value(:stats_building_repairs, -object[:damage])
          when "vehicle"
            player.increment_value(:stats_vehicle_repairs, -object[:damage]) if obj && obj[:drivers].positive? # only count occupied vehicles
          when "soldier"
            player.increment_value(:stats_healed, -object[:damage])
          end
        else
          case object[:type].downcase.strip
          when "building"
            player.increment_value(:stats_building_damage, object[:damage])
          when "vehicle"
            player.increment_value(:stats_vehicle_damage, object[:damage]) if obj && obj[:drivers].positive? # only count occupied vehicles
          when "soldier"
            player.increment_value(:stats_damage, object[:damage])
          end
        end

        object[:_damager_object] = damager
        object[:_player_object] = player
      end

      PluginManager.publish_event(:damaged, object, data)

      pp object if Config.debug_verbose
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
      object[:killed_facing]    = data[7].to_f

      object[:killer_object]    = data[8]
      object[:killer_preset]    = data[9]
      object[:killer_x]         = data[10].to_f
      object[:killer_y]         = data[11].to_f
      object[:killer_z]         = data[12].to_f
      object[:killer_facing]    = data[13].to_f
      object[:killer_weapon]    = data[14]

      # Additions
      object[:killed_preset_name] = data[15]
      object[:killer_preset_name] = data[16]
      object[:killer_name]        = data[17] # Yes, it's killeR [2023-04-21]
      object[:killed_name]        = data[18] # then killeD

      Presets.learn(preset: object[:killed_preset], name: object[:killed_preset_name])
      Presets.learn(preset: object[:killer_preset], name: object[:killer_preset_name])

      killed_obj = @game_objects[object[:killed_object]]
      killer_obj = @game_objects[object[:killer_object]]

      if killed_obj && killer_obj
        killed_obj[:killed] = true

        case object[:killed_type].downcase
        when "building"
          killed_building(object, killed_obj, killer_obj)
        when "vehicle"
          killed_vehicle(object, killed_obj, killer_obj)
        when "soldier"
          killed_soldier(object, killed_obj, killer_obj)
        end
      end

      object[:_killed_object] = killed_obj if killed_obj
      object[:_killer_object] = killer_obj if killer_obj

      PluginManager.publish_event(:killed, object, data)

      pp object if Config.debug_verbose
    end

    def killed_building(object, killed_obj, killer_obj)
      RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{killer_obj[:name]} destroyed the #{Presets.translate(object[:killed_preset])}.") if Config.messages[:building_killed]

      killer_player_data = PlayerData.player(PlayerData.name_to_id(killer_obj[:name].to_s.downcase))

      killer_player_data&.increment_value(:stats_buildings_destroyed)
    end

    def killed_vehicle(object, killed_obj, killer_obj)
      # RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{killer_obj[:name]} destroyed the #{object[:killed_preset]}.") if Config.messages[:vehicle_killed]

      _killed_obj = @game_objects[killed_obj[:driver]]
      killed_player_data = PlayerData.player(PlayerData.name_to_id(_killed_obj[:name].to_s.downcase)) if _killed_obj
      killer_player_data = PlayerData.player(PlayerData.name_to_id(killer_obj[:name].to_s.downcase)) if killer_obj

      killed_player_data&.increment_value(:stats_vehicles_lost)
      killer_player_data&.increment_value(:stats_vehicles_destroyed)
    end

    def killed_soldier(object, killed_obj, killer_obj)
      PlayerData.player(PlayerData.name_to_id(killed_obj[:name]))&.increment_value(:stats_deaths)

      case killer_obj[:type].downcase
      when "soldier"
        if killed_obj[:name] == killer_obj[:name]
          RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{killer_obj[:name]} killed theirself.") if Config.messages[:soldier_killed]
        else
          PlayerData.player(PlayerData.name_to_id(killer_obj[:name]))&.increment_value(:stats_kills)
        end
      when "vehicle" # THIS ONLY TRIGGERS WITH AI HARVESTERS for some reason...
        RenRem.cmd("cmsg 255,127,0 [MOBIUS] #{killed_obj[:name]} was ran over by a #{Presets.translate(object[:killer_preset])}.") if Config.messages[:soldier_killed]
      end
    end

    # PURCHASED;CHARACTER;cyberarm;Soviet_Technician;Technician
    def purchased(line)
      data = line.split(";")
      object = {}

      # TODO: validate these keys
      object[:type]        = data[1]
      object[:name]        = data[2] # player name
      object[:preset]      = data[3]
      object[:preset_name] = data[4]

      Presets.learn(preset: object[:preset], name: object[:preset_name])

      game_obj = @game_objects[@current_players[object[:name]]]

      return unless game_obj

      player_team = game_obj[:team]
      object[:object] = game_obj[:object]

      case object[:type].downcase
      when "character"
        RenRem.cmd("cmsgt #{player_team} 255,127,0 [MOBIUS] #{object[:name]} changed to #{object[:preset_name]}") if Config.messages[:soldier_purchase]
      when "vehicle"
        RenRem.cmd("cmsgt #{player_team} 255,127,0 [MOBIUS] #{object[:name]} purchased a #{object[:preset_name]}") if Config.messages[:vehicle_purchase]
      end

      object[:_player_object] = game_obj

      PluginManager.publish_event(:purchased, object, data)

      pp object if Config.debug_verbose
    end

    # APB seems to be reporting player credits here: SCORE;1500000729;0;1648
    def score(line)
      data = line.split(";")
      object = {}

      # TODO: Validate thise keys
      object[:object]  = data[1]
      object[:score]   = data[2]
      object[:credits] = data[3]

      PluginManager.publish_event(:score, object, data)

      pp object if Config.debug_verbose
    end

    def win(line)
      data = line.split(";")

      object = {
        winning_team_name: data[1],
        win_type: data[2],
        team_0_score: data[3],
        team_1_score: data[4]
      }

      PluginManager.publish_event(:win, object, data)
      Presets.save_presets

      clear_data(object)
    end

    def maploaded(line)
      return unless Config.record_gamelog

      @data_recorder&.close
      @data_recorder = File.open("#{ROOT_PATH}/data/gamelog_#{Time.now.strftime('%Y-%m-%d-%s')}.dat", "a+")
      @data_recorder.puts(line)
    end

    def config(line)
      # TODO: RESET DATA FOR NEXT GAME

      clear_data
    end

    def chat(line)
      # ARRRRRRRRRRRGGGGGGGGGGG!!!!!
      # Agent Mobius can't come soon enough! :scream:

      # data = line.split(";")
      # team_chat = data[1].downcase.strip == "public"
      # object_id = data[2]
      # message   = data[3]

      # return unless data[1].downcase =~ /public|team/ # Prevent passing garbage from /username PMs

      # username, object_id = @current_players.find { |name, obj| obj == object_id }

      # player = PlayerData.player(PlayerData.name_to_id(username))
      # return unless player

      # # TODO: Detect if player is mod or admin and format their name as such

      # if team_chat && true # TODO: Add option for whether team chat is published to IRC
      #   # TODO: Publish formatted message to IRC
      # else
      #   # TODO: Publish formatted message to IRC
      # end

      # if message.start_with?("!")
      #   PluginManager.handle_command(player, message)
      # else
      #   PluginManager.publish_event(
      #     team_chat ? :team_chat : :chat,
      #     player,
      #     message
      #   )
      # end
    end

    def clear_data(win_data = nil)
      @game_objects.clear
      @current_players.clear

      # ignore CONFIG gamelog event
      if win_data
        # Create a dummy playerdata player object
        tally = PlayerData::Player.new(origin: "NULL", id: "", name: "", join_time: nil, score: 0, team: -1, ping: 0, address: ";", kbps: 0, rank: 0, kills: 0, deaths: 0, money: 0, kd: 0, time: nil, last_updated: nil)
        player_list = PlayerData.player_list

        player_list.each do |player|
          player.increment_value(:stats_score, player.score)

          player.score = 0

          player.data.each do |key, value|
            tally.increment_value(key, value)
          end
        end

        player_list.each do |player|
          player.update_rank_data(win_data, tally)
        end
      end

      PlayerData.player_list.each(&:reset)

      @last_purchase_team_one = nil
      @last_purchase_team_two = nil
    end
  end
end
