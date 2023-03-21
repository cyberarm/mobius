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

    def self.instance
      @@instance
    end

    def self.teardown
      log("TEARDOWN", "Shutdown RenRem...")

      @@instance&.teardown
    end

    def self.cmd(data, delay = nil, &block)
      raise "RenRem not running!" unless @@instance

      if delay
        @@instance.cmd_delayed(data, delay, block)
      else
        @@instance.cmd(data, block)
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

      raise "Password length must be 8 characters long, got: #{@password.length}" if @password.length != 8

      @checksum_factor_cache = 2**32

      @socket = UDPSocket.new
      @socket.connect(@address, @port)

      @queue = []
      @delayed_queue = []
    end

    def drain
      # Always send password for the first command
      # Password isn't needed for subsequent commands for this method call
      send_password = true

      while (command = @queue.shift)
        deliver_command(command, send_password)
        send_password = false
      end

      delayed = @delayed_queue.select { |c| monotonic_time - c.queued_time >= c.delay }
      delayed.each do |comm|
        @delayed_queue.delete(comm)

        deliver_command(comm, send_password)
        send_password = false
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
        @delayed_queue << Command.new(command: data, queued_time: monotonic_time, delay: delay, block: block)
      else
        @queue << Command.new(command: data, queued_time: monotonic_time, delay: delay, block: block)
      end
    end

    def deliver_command(command, send_password)
      # Quite verbose, enable for debugging
      # log "RENREM", "Sent command '#{command.command[0..249]}' to RenRem!"
      # t = monotonic_time

      log "RENREM", "WARNING: attempt to send more than 249 characters to renrem detected!" unless command.command.length <= 249

      # Drain potential garbage that appears on level change/load.
      # Don't wait for packet as there shouldn't be a packet most of the time.
      drain_socket(timeout: 0)

      if send_password
        @socket.send(encode_data(@password), 0)
        password_response = drain_socket
      end

      # Actually send command to RenRem
      @socket.send(encode_data(command.command[0..249]), 0)
      response = drain_socket

      command.block&.call(response)
      # log "Completed command after: #{(monotonic_time - t.round(2))}s"
    rescue Errno::ECONNREFUSED
      log "RENREM", "Failed to send command '#{command.command}' to RenRem!"
    end

    def drain_socket(timeout: 1.0)
      begin
        IO.select([@socket], nil, nil, timeout)
        buffer = []

        while (response = decode_data(@socket.recv_nonblock(65_000)))
          buffer << response
        end
      rescue IO::WaitReadable # Done receiving response from FDS/RenRem
        return buffer.join
      rescue Errno::ECONNREFUSED
        log "RENREM", "Unable to connect to RemRem!"
      rescue => e
        puts e
        puts e.backtrace
      end
    end

    def cmd(data, block)
      queue_command(data, nil, block)
    end

    def cmd_delayed(data, seconds, block)
      queue_command(data, seconds, block)
    end

    def teardown
      @socket&.close
    end
  end
end
