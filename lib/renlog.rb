module Mobius
  class RenLog
    @@instance = nil

    def self.init
      log("INIT", "Enabling RenLog...")
      new
    end

    def self.teardown
      log("INIT", "Shutdown RenLog...")
    end

    def self.feed(line)
      @@instance&.parse_line(line)
    end

    def parse_line(line)
      pp [:renlog, line]
    end
  end
end
