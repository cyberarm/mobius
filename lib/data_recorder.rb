# frozen_string_literal: true

module Mobius
  class DataRecorder
    SCHEMA_VERSION = 1
    HEADER = "Z*CQ".freeze
    HEADER_BYTE_SIZE = 7 + 1 + 8

    GAMEMESSAGE_CHUNK = 0
    GAMELOG_CHUNK = 1
    RENLOG_CHUNK = 2

    def self.delog(file)
      header = []

      File.open(file, "r") do |f|
        header_line = true
        f.each_line do |line|
          line = line.strip

          if header_line
            header_line = false
            header = line.unpack("#{HEADER}")
            puts "#{header[0]}v#{header[1]} #{Time.at(header[2])}"

            next
          end

          chunk = line.unpack("GCZ*")
          puts chunk

          case chunk[1]
          when GAMEMESSAGE_CHUNK
          when GAMELOG_CHUNK
          when RENLOG_CHUNK
          end
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

    def log(stream = :gamelog, event)
      init_log_file unless @file

      data = event.split(" ", 2).last # drop somewhat useless [HH:mm:ss] bit of event message to be replaced with monotonic (milli)seconds

      chunk_type = case stream
      when :gamemessage
        GAMEMESSAGE_CHUNK
      when :gamelog
        GAMELOG_CHUNK
      when :renlog
        RENLOG_CHUNK
      else
        raise "Unknown stream type: #{stream}"
      end

      @file.puts([monotonic_time - @seconds, chunk_type, data].pack("GCZ*"))
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
  end
end
