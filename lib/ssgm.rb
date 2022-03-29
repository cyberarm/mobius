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

    def initialize(address:, port:)
      raise "SSGM instance already active!" if @@instance

      @@instance = self

      @address = address
      @port = port

      @socket = TCPSocket.new(@address, @port)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      monitor_stream
    end

    def monitor_stream
      Thread.new do
        @socket.each_line do |line|
          line.strip.split("\0").each do |event|
            type = event[0..2]

            event.sub!(type, "")

            case Integer(type)
            when 0 # SSGMLog
              feed(event)
            when 1 # GameLog
              GameLog.feed(event)
            when 2 # RenLog
              RenLog.feed(event)
            # when 3 # IGNORE
            end
          end
        end
      end
    end

    def feed(line)
      pp [:ssgm, line]
    end

    def teardown
      @socket&.close
    end
  end
end
