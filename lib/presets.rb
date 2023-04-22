module Mobius
  class Presets
    PATH = "#{ROOT_PATH}/conf/presets.json".freeze

    def self.init
      log("INIT", "Enabling Preset Translation...")

      @presets = {}

      load_presets
    end

    def self.translate(preset)
      @presets[preset.to_sym] || preset
    end

    def self.learn(preset:, name:)
      # Soldiers that are human players also have their *current* weapon name included, we drop that
      @presets[preset.to_sym] = name.split("/", 2).first
    end

    def self.teardown
      log("INIT", "Shutdown Preset Translation...")

      save_presets
    end

    def self.load_presets
      return unless File.exist?(PATH)

      @presets = JSON.parse(File.read(PATH), symbolize_names: true)
    end

    def self.save_presets
      File.write(PATH, JSON.pretty_generate(@presets.sort_by { |key, _value| key.to_s.downcase }.to_h))
    end
  end
end
