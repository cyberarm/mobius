# frozen_string_literal: true

module Mobius
  class DataRecorder
    SCHEMA_VERSION = 0
    HEADER = "Z*CQ".freeze
    HEADER_BYTE_SIZE = 7 + 1 + 8

    GAMELOG_CHUNK = 1
    RENLOG_CHUNK = 2

    EVENTS = {
      :gamelog_crate => "Z*CZ*ggggggN",
      :gamelog_created => "Z*NZ*ggggggggcZ*",
      :gamelog_destroyed => "Z*NZ*gggg",
      :gamelog_pos => "", # NO OP
      :gamelog_enter_vehicle => "NZ*gggNZ*ggg",
      :gamelog_exit_vehicle => "NZ*gggNZ*ggg",
      :gamelog_damaged => "Z*NZ*ggggNZ*ggggggg",
      :gamelog_killed => "Z*NZ*ggggNZ*ggggZ*Z*Z*Z*Z*",
      :gamelog_purchased => "Z*Z*Z*Z*",
      :gamelog_score => "NNN",
      :gamelog_win => "Z*Z*NN",
      :gamelog_maploaded => "Z*",
      :gamelog_config => "NZ*",
      :gamelog_chat => "",

      :renlog => "Z*"
    }.freeze

    EVENT_BYTE_SIZES = []

    EVENT_ENTITY_TYPE = %w[
      SOLDIER
      VEHICLE
      BUILDING
    ]

    def self._calculate_base_offsets
      i = 0

      EVENTS.each do |key, pattern|
        offset = 0

        pattern.each_char do |char|
          case char
          when "C", "c"
            offset += 1
          when "N", "g"
            offset += 4
          when "Q", "G"
            offset += 8
          when "*", "Z" # NO OP
          else
            raise "Unknown size for char: #{char}"
          end
        end


        EVENT_BYTE_SIZES[i] = offset
        i += 1
      end
    end

    def self.delog(file)
      e_k_s = EVENTS.keys.size
      v_a = EVENTS.values

      string = File.read(file)
      s_s = string.size
      offset = 0

      header = string.unpack("#{HEADER}")
      offset += HEADER_BYTE_SIZE
      puts "#{header[0]}v#{header[1]} #{Time.at(header[2])}"

      while (offset < s_s + 9)
        # pp offset
        chunk_header = string.unpack("GC", offset: offset + 1)
        offset += 8 + 1 # offset_size(chunk_header, "GC")

        case chunk_header[1]
        when GAMELOG_CHUNK
          chunk_type = string.unpack1("C", offset: offset + 1)
          offset += 1

          # pp EVENTS.keys[chunk_type]
          # pp offset
          chunk = string.unpack(v_a[chunk_type], offset: offset + 1)
          offset += offset_size(chunk, chunk_type)
          # pp chunk
        when RENLOG_CHUNK
          chunk = string.unpack(EVENTS[:renlog], offset: offset + 1)
          offset += offset_size(chunk, e_k_s - 1)

          # pp chunk
        end
      end
    end

    def self.offset_size(array, key_index)
      string_lengths = 0

      array.each do |a|
        next unless a.is_a?(String)

        string_lengths += a.size + 1
      end

      string_lengths + EVENT_BYTE_SIZES[key_index]
    end

    def initialize
      @seconds = monotonic_time
      @filename = nil
      @file = nil
    end

    def init_log_file
      @seconds = monotonic_time

      FileUtils.mkdir_p("#{ROOT_PATH}/data")
      @filename = "#{ROOT_PATH}/data/gamelog_#{Time.now.strftime('%Y-%m-%d-%s')}.dat"
      @file = File.open(@filename, "a+b")
      @file.sync = true
      @file.puts(["MOBIUS", SCHEMA_VERSION, Time.now.to_i].pack(HEADER))
    end

    def log(stream = :gamelog, event, data)
      init_log_file unless @file

      case stream
      when :gamelog
        index = EVENTS.keys.index(:"#{stream}_#{event}")
        pp [monotonic_time - @seconds, 1, index, :"#{stream}_#{event}", data.values, "GCC#{EVENTS[:"#{stream}_#{event}"]}"]
        @file.write([monotonic_time - @seconds, 1, index, data.values].flatten.pack("GCC#{EVENTS[:"#{stream}_#{event}"]}"))
      when :renlog
        @file.write([monotonic_time - @seconds, 2, data].pack("GC#{EVENTS[:"#{stream}"]}"))
      else
        raise "Unknown stream type: #{stream}"
      end
    end

    def close
      @file&.close

      # Compress log file as the renlog bit of it can easily be significantly compressed
      Zip::File.open("#{@filename}.zip", create: true) do |zf|
        zf.add(File.basename(@filename), @filename)
      end

      # Delete fat file if the zipped file saved
      if File.exist?("#{@filename}.zip") && File.size("#{@filename}.zip") > 0
        File.delete(@filename)
      end

      @filename = nil
      @file = nil
    end

    _calculate_base_offsets
  end
end
