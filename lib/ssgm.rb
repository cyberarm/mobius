module Mobius
  class SSGM
    @@instance = nil

    def self.init
      log("INIT", "Connecting to SSGM 4...")

      new(
        address: Config.ssgm_address,
        port: Config.ssgm_port
      )
    end

    def self.teardown
      log("TEARDOWN", "Shutdown SSGM...")

      @@instance&.teardown
    end

    def self.cmd(data, delay = nil)
      raise "RenRem not running!" unless @@instance

      if delay
        @@instance.cmd_delayed(data, delay)
      else
        @@instance.cmd(data)
      end
    end

    def self.parse_tt_rotation
      @@instance&.parse_tt_rotation
    end

    def initialize(address:, port:)
      raise "SSGM instance already active!" if @@instance

      @@instance = self

      @address = address
      @port = port

      @lost_connection = false

      parse_tt_rotation

      monitor_stream
    end

    def parse_tt_rotation
      ServerConfig.rotation.clear

      reading_rotation = false
      File.open("#{Config.fds_path}/tt.cfg") do |f|
        f.each_line do |line|
          line = line.strip

          if line.start_with?("rotation:")
            reading_rotation = true
          elsif reading_rotation
            break if line.start_with?("];")
            next unless line.start_with?("\"")

            _, name = line.split('"')
            ServerConfig.rotation << name
          end
        end
      end
    end

    def monitor_stream
      Thread.new do
        begin
          @socket = TCPSocket.new(@address, @port)
          @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

          log("SSGM", "Connected to SSGM.")

          if @lost_connection
            @lost_connection = false

            # Purge player data
            PlayerData.player_list.each do |player|
              PluginManager.publish_event(:player_left, player)
              log "Deleting data for player #{player.name} (ID: #{player.id})"
              PlayerData.delete(player)
            end

            PluginManager.reset_blackboard!

            # Soft re-init Mobius on server crash
            SSGM.parse_tt_rotation
            Config.reload_config

            PluginManager.reload_enabled_plugins!

            ServerConfig.fetch_available_maps

            RenRem.cmd("mapnum")
            RenRem.cmd("sversion")
          end

          while (event = @socket.gets("\0")&.strip)
            type = event[0..2]

            event.sub!(type, "")

            id = -1
            begin
              id = Integer(type)
            rescue ArgumentError # Unexpected line starter, game_info data?
              id = -1
            end

            case id
            when 0 # SSGMLog
              feed(event)
            when 1 # GameLog
              GameLog.feed(event)
            when 2 # RenLog
              RenLog.feed(event)
            else
              # Enable when debugging
              # pp [:unhandled_event, type, event]
            end
          end

          raise "Lost connection to SSGM."
        rescue SystemCallError, StandardError => e
          log("SSGM", "An error occurred while attempting to communicate with SSGM. Retrying in 10s...")
          log "SSGM", "#{e.class}: #{e}"
          puts e.backtrace

          @socket&.close unless @socket&.closed?
          @socket = nil

          if e.class == Errno::ECONNREFUSED
            @lost_connection = true
          end

          sleep 10

          monitor_stream
        end
      end
    end

    def feed(line)
      pp [:ssgm, line] if Config.debug_verbose
    end

    def teardown
      @socket&.close
    end
  end
end
