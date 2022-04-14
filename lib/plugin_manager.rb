module Mobius
  class PluginManager
    @@known_plugins = []
    @@plugins = []

    def self.init
      log("INIT", "Initializing plugins...")

      find_plugins
      init_plugins
    end

    def self.teardown
      log("TEARDOWN", "Shutdown plugins...")
    end


    def self.find_plugins
      Dir.glob("#{ROOT_PATH}/plugins/*.rb").each do |plugin|
        next # REMOVE ME

        begin
          load plugin
        rescue => e
          puts "Failed to load plugin: #{File.basename(plugin)}"
          raise
        end
      end
    end

    def self.register_plugin(klass)
      @@known_plugins << klass
    end

    def self.init_plugins
      @@known_plugins.each do |klass|
        @@plugins << klass.new
      end

      @@plugins.each(&:start)
    end

    def self.publish_event(event, *args)
      @@plugins.each do |plugin|
        plugin.event(event, *args)
      end
    end
  end
end
