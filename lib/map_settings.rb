module Mobius
  class MapSettings
    extend Common

    @@instance = nil

    def self.init
      Mobius.log("INIT", "Enabling MapSettings...")
      new
    end

    def self.teardown
      Mobius.log("TEARDOWN", "Shutdown MapSettings...")
    end

    def self.apply_map_settings(apply_time: true)
      return unless @@instance

      time           = get_map_setting(:time, -1)
      mine_limit     = get_map_setting(:mines, -1)
      vehicle_limit  = get_map_setting(:vehicles, -1)
      aircraft_limit = get_map_setting(:aircraft, -1)
      vessels_limit  = get_map_setting(:vessels, -1)
      botcount       = get_map_setting(:botcount, 0)
      rules          = get_map_setting(:rules, "")

      RenRem.cmd("time #{time * 60}") if apply_time && time && time.is_a?(Numeric)
      RenRem.cmd("mlimit #{mine_limit}") unless mine_limit.negative?
      RenRem.cmd("vlimit #{vehicle_limit}") unless vehicle_limit.negative?
      RenRem.cmd("alimit #{aircraft_limit}") unless aircraft_limit.negative?
      RenRem.cmd("nlimit #{vessels_limit}") unless vessels_limit.negative?
      RenRem.cmd("botcount #{botcount}")

      unless rules.empty?
        after(5) do
          broadcast_message("[MOBIUS] Special rules for #{ServerStatus.get(:current_map)}: #{rules}", red: 255, green: 127, blue: 0)
        end
      end
    end

    def self.get_map_setting(setting, default_value)
      return default_value unless @@instance

      map = ServerStatus.get(:current_map)

      default_setting = @@instance.data.dig(:defaults, setting)
      map_setting = @@instance.data.dig(:maps, map.to_sym, setting)

      map_setting ? map_setting : default_setting
    end

    attr_reader :data

    def initialize(path: "#{ROOT_PATH}/conf/map_settings.json")
      return unless File.exist?(path)

      @@instance = self

      @data = JSON.parse(File.read(path), symbolize_names: true).freeze
    end
  end
end
