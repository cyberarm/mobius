module Mobius
  class RenRem
    @@instance = nil
    @@queue = []

    def self.init
      log("INIT", "Enabling RenRem access...")

      new(
        address: Config.renrem_address,
        port: Config.renrem_port,
        password: Config.renrem_password
      )
    end

    def self.queue
      @@queue
    end

    def self.teardown
      log("TEARDOWN", "Shutdown RenRem...")

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

    # Queue command for single execution on next tick (Repeated calls will be ignored in the same tick)
    def self.enqueue(data)
      @@queue << data
      @@queue.uniq!
    end

    Command = Struct.new(:command, :queued_time, :delay, :block)

    def initialize(address:, port:, password:)
      raise "RenRem instance already active!" if @@instance

      @@instance = self

      @@queue = []

      @address = address
      @port = port
      @password = password

      # TODO: FAIL IF PASSWORD != 8

      @password_last_used = 0.0
      @password_session = 50.0 # seconds

      @checksum_factor_cache = 2**32

      @socket = UDPSocket.new
      @socket.connect(@address, @port)

      @queue = []
      @delayed_queue = []

      start
    end

    def start
      Thread.new do
        until @socket.closed?
          while (command = @queue.shift)
            deliver_command(command.command)
          end

          delayed = @delayed_queue.select { |c| Time.now - c.queued_time >= c.delay }
          delayed.each do |comm|
            @delayed_queue.delete(comm)

            deliver_command(comm.command)
          end

          sleep 0.01
        end
      end
    end

    def encode_data(data)
      length_with_checksum = data.length + 5
      length = length_with_checksum - 4
      checksum = 0

      password_array = @password.bytes

      # Unpack bytes
      msgbuf = [data].pack("x8 a#{length} x").unpack("C8 C#{length}")

      # Encrypt message
      length_with_checksum.times do |i|
        password_array[i % 8] ^= (msgbuf[i + 4] = (((((0xff << 8) | (msgbuf[i + 4] + i)) - 0x32) & 0xff) ^ password_array[i % 8]))
      end

      # Pack msgbuf
      msgbuf = msgbuf.pack("C8 C#{length}")

      # Calculate checksum
      i = 0
      while(i < length_with_checksum)
        checksum = (checksum >> 0x1f) + checksum * 2

        if i + 4 > length_with_checksum
          buflen = msgbuf.length
          tempbuf = [msgbuf.unpack("C#{buflen}"), 0, 0, 0].flatten.pack("C#{buflen + 3}")
          checksum += tempbuf.unpack1("x4 x#{i} I")
        else
          checksum += msgbuf.unpack1("x4 x#{i} I")
        end

        while(checksum > @checksum_factor_cache)
          checksum -= @checksum_factor_cache
        end

        i += 4
      end

      [[checksum].pack("I").unpack("C*"), msgbuf.unpack("x4 C#{length_with_checksum}")].flatten.pack("C*")
    end

    def decode_data(data)
      password_array = @password.bytes
      length = data.length - 4

      msgbuf = data.unpack("C4 C#{length}")

      length.times do |i|
        j = password_array[i % 8]
        password_array[i % 8] = msgbuf[i + 4] ^ password_array[i % 8]
        msgbuf[i + 4] = ([(msgbuf[i + 4] ^ j)].pack("C").unpack1("c") - i + 0x32) % 128
      end

      msgbuf[8..msgbuf.length].map(&:chr).join.chomp("\x00")
    end

    def queue_command(data, delay, block)
      if delay
        @delayed_queue << Command.new(command: data, queued_time: Time.now, delay: delay, block: block)
      else
        @queue << Command.new(command: data, queued_time: Time.now, delay: delay, block: block)
      end
    end

    def deliver_command(data)
      # Quite verbose, enable for debugging
      # log "RENREM", "Sent command '#{data[0..249]}' to RenRem!"

      log "RENREM", "WARNING: attempt to send more than 249 characters to renrem detected!" unless data.length <= 249

      # We don't need to send the password EVERY time, send it only if last sent more then ~50 seconds ago
      if (Time.now.to_i - @password_last_used.to_i) >= @password_session
        @password_last_used = Time.now
        @socket.send(encode_data(@password), 0)
      end

      # Actually send command to RenRem
      @socket.send(encode_data(data[0..249]), 0)
    rescue Errno::ECONNREFUSED
      log "RENREM", "Failed to send command '#{data}' to RenRem!"
    end

    def cmd(data)
      queue_command(data, nil, nil)
    end

    def cmd_delayed(data, seconds, &block)
      queue_command(data, seconds, block)
    end

    def teardown
      @socket&.close
    end
  end
end
