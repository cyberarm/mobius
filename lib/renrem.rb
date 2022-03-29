module Mobius
  class RenRem
    @@instance = nil

    def self.init
      log("INIT", "Connecting to RenRem...")

      new(
        address: Config.renrem_address,
        port: Config.renrem_port,
        password: Config.renrem_password
      )
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

    def initialize(address:, port:, password:)
      raise "RenRem instance already active!" if @@instance

      @@instance = self

      @address = address
      @port = port
      @password = password

      # TODO: FAIL IF PASSWORD != 8

      @checksum_factor_cache = 2**32

      @socket = UDPSocket.new
      @socket.connect(@address, @port)
    end

    def encode_data(data)
      length_with_chksum = data.length + 5
      length = data.length
      checksum = 0

      password_array = @password.bytes

      # Unpack bytes
      msgbuf = [data].pack("x8 a#{length} x").unpack("C8 C#{length}")

      # Encrypt message
      length.times do |i|
        password_array[i % 8] ^= (msgbuf[i + 4] = (((((0xff << 8) | (msgbuf[i + 4] + i)) - 0x32) & 0xff) ^ password_array[i % 8]))
      end

      # Pack msgbuf
      msgbuf = msgbuf.pack("C8 C#{length}")

      # Calculate checksum
      i = 0
      while(i < length) do
        checksum = (checksum >> 0x1f) + checksum * 2

        if i + 4 > length
          bl = length % 4 # Unused?
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

      # $msgbuf = pack (" C4 C$length", unpack("C4", pack('I', $chksum)), unpack("x4 C$length", $msgbuf));
      puts
      pp msgbuf.unpack("x4 C*").pack("C*"), msgbuf.unpack("x4 C*").length, length
      puts
      c = [[checksum].pack("I").unpack("C*"), msgbuf.unpack("x4 C#{length}")].flatten
      pp c, c.length, length
      p c.pack("C*")
      puts

      # FIXME: MISSING last 4 characters!
      [[checksum].pack("I").unpack("C*"), msgbuf.unpack("x4 C#{length}")].flatten.pack("C*")
    end

    def decode_data(data)
      password_array = @password.bytes
      length = data.length - 4

      msgbuf = data.unpack("C4 C#{length}")

      length.times do |i|
        j = password_array[i % 8]
        password_array[i % 8] = msgbuf[i + 4] ^ password_array[i % 8]
        # Maybe correct?
        # msgbuf[i + 4] = ( unpack("c", pack("C",($msgbuf[$i + 4] ^ $p))) - $i + 50);
        msgbuf[i + 4] = [(msgbuf[i + 4] ^ j)].pack("C").unpack1("c") - i + 50
      end

      msgbuf[8..msgbuf.length].map(&:chr).join
    end

    def cmd(data)
      # TODO: Limit data length

      d = encode_data(data)
      pp decode_data(d)

      # @socket.send(encode_data(@password), 0)
      # @socket.send(encode_data(data), 0)
      # @socket.recv
    end

    def cmd_delayed(data, seconds)
    end

    def teardown
      @socket&.close
    end
  end
end
