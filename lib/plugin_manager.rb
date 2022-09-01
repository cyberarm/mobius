module Mobius
  class PluginManager
    @plugins = []
    @commands = {}
    @deferred = []

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
        # next # REMOVE ME

        begin
          register_plugin(plugin)
        rescue => e
          puts "Failed to load plugin: #{File.basename(plugin)}"
          raise
        end
      end
    end

    def self.register_plugin(plugin_file)
      @plugins << Plugin.new(plugin_file)
    end

    def self.init_plugins
      @plugins.each do |plugin|
        next if plugin.___data[:plugin_disabled]

        log "PLUGIN MANAGER", "Loaded plugin: #{plugin.___name}"

        deliver_event(plugin, :start, nil)
      end
    end

    def self.register_command(command)
      pp command
    end

    def self.publish_event(event, *args)
      if event == :tick
        @deferred.each do |timer|
          timer.ticks += 1

          if timer.ticks >= timer.delay
            timer.block&.call
            @deferred.delete(timer)
          end
        end
      end

      @plugins.each do |plugin|
        deliver_event(plugin, event, *args)
      end
    end

    def self.deliver_event(plugin, event, *args)
      plugin.___tick if event == :tick

      handlers = plugin.___event_handlers[event]

      return unless handlers.is_a?(Array)

      handlers.each do |handler|
        begin
          handler.call(*args)
        rescue StandardError => e
          log "PLUGIN MANAGER", "An error occurred while delivering event: #{event}, for plugin: #{plugin.___name}"
          log "ERROR", e
        end
      end
    end

    # Delay delivery of event/block until the backend has done it's thing
    def self.defer(seconds, &block)
      @deferred << Plugin::Timer.new(:after, 0, seconds, block)
    end
  end
end
