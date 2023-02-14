module Mobius
  class MapSettings
    @@instance = nil

    def self.init
      log("INIT", "Enabling MapSettings...")
      new
    end

    def self.teardown
      log("TEARDOWN", "Shutdown MapSettings...")
    end

    def self.apply_map_settings(apply_time: true)
      return unless @@instance

      time          = get_map_setting(:time)
      mine_limit    = get_map_setting(:mines)
      vehicle_limit = get_map_setting(:vehicles)
      rules         = get_map_setting(:rules)

      RenRem.cmd("time #{time * 60}") if apply_time && time && time.is_a?(Numeric)
      RenRem.cmd("mlimit #{mine_limit}")
      RenRem.cmd("vlimit #{vehicle_limit}")

      RenRem::cmd("msg [MOBIUS] Special rules for #{ServerStatus.get(:current_map)}: #{rules}", 5) unless rules.empty?
    end

    def self.get_map_settings(setting)
      map = ServerStatus.get(:current_map)

      default_setting = MapSettings.data.dig(:defaults, setting)
      map_setting = MapSettings.data.dig(:maps, map, setting)

      map_setting ? map_setting : default_setting
    end

    attr_reader :data

    def initialize(path: "#{ROOT_PATH}/conf/map_settings.json")
      @@instance = self

      @data = JSON.parse(File.read(path), symbolize_names: true).freeze

      pp @data
    end
  end
end
