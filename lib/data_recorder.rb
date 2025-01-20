module Mobius
  class DataRecorder
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

    EVENT_ENTITY_TYPE = %w[
      SOLDIER
      VEHICLE
      BUILDING
    ]

    def initialize
      @file = nil

      init_log_file
    end

    def init_log_file
      FileUtils.mkdir_p("#{ROOT_PATH}/data")
      @file = File.open("#{ROOT_PATH}/data/gamelog_#{Time.now.strftime('%Y-%m-%d-%s')}.dat", "a+b")
      @file.write(["mobius", Time.now.to_i].pack("Z*Q"))
    end

    def log(stream = :gamelog, event, data)
      init_log_file unless @file

      case stream
      when :gamelog
        index = EVENTS.keys.index(:"#{stream}_#{event}")
        # pp [monotonic_time, 1, index, :"#{stream}_#{event}", data.values, "GCC#{EVENTS[:"#{stream}_#{event}"]}"]
        @file.write([monotonic_time, 1, index, data.values].flatten.pack("GCC#{EVENTS[:"#{stream}_#{event}"]}"))
      when :renlog
        @file.write([monotonic_time, 2, data].pack("GC#{EVENTS[:"#{stream}"]}"))
      else
        raise "Unknown stream type: #{stream}"
      end
    end

    def close
      @file&.close
      @file = nil
    end
  end
end
