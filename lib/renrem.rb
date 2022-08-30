module Mobius
  class RenRem
    @@instance = nil

    def self.init
      log("INIT", "Enabling RenRem access...")

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
        # Maybe correct?
        # msgbuf[i + 4] = ( unpack("c", pack("C",($msgbuf[$i + 4] ^ $p))) - $i + 50);
        msgbuf[i + 4] = [(msgbuf[i + 4] ^ j)].pack("C").unpack1("c") - i + 50
      end

      msgbuf[8..msgbuf.length].map(&:chr).join
    end

    def cmd(data)
      # TODO: Limit data length

      @socket.send(encode_data(@password), 0)
      @socket.send(encode_data(data), 0)
    end

    def cmd_delayed(data, seconds)
      Thread.new do
        sleep seconds

        cmd(data)
      end
    end

    def teardown
      @socket&.close
    end
  end
end
