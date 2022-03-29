module Mobius
  class Plugin
    # include PluginEvents

    def self.inherited(klass)
      log "PLUGIN", "Found #{klass}"

      PluginManager.register_plugin(klass)
    end

    def renrem_cmd(data, delay = nil)
      RenRem.cmd(data, delay)
    end

    # RESERVED
    def initialize
    end

    def event(event, *args)
      self.send(event, *args)
    end

    def name
      self.class.to_s
    end

    def start
    end

    def tick
    end

    def teardown
    end
  end
end
