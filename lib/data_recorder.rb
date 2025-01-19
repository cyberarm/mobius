module Mobius
  class DataRecorder
    EVENTS = {
      :gamelog_crate => "ZCZggggggN",
      :gamelog_created => "ZZZggggggggcZ",
      :gamelog_destroyed => "ZZZgggg",
      :gamelog_pos => "", # NO OP
      :gamelog_enter_vehicle => "",
      :gamelog_exit_vehicle => "",
      :gamelog_damaged => "",
      :gamelog_killed => "",
      :gamelog_purchased => "",
      :gamelog_score => "",
      :gamelog_win => "",
      :gamelog_maploaded => "",
      :gamelog_config => "",
      :gamelog_chat => "",

      :renlog => "c*"
    }.freeze

    def initialize
      @file = nil

      init_log_file
    end

    def init_log_file
      FileUtils.mkdir_p("#{ROOT_PATH}/data")
      @file = File.open("#{ROOT_PATH}/data/gamelog_#{Time.now.strftime('%Y-%m-%d-%s')}.dat", "a+b")
      @file.write(["mobius", Time.now.to_i].pack("c6Q"))
    end

    def log(stream = :gamelog, event, data)
      init_log_file unless @file

      case stream
      when :gamelog
        index = EVENTS.index(:"#{stream}_#{event}")
        @file.write([monotonic_time, 1, index, data.to_a].flatten.pack("NCC#{EVENTS[:"#{stream}_#{event}"]}"))
      when :renlog
        @file.write([monotonic_time, 2, data].pack("NCC#{EVENTS[:"#{stream}"]}"))
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
