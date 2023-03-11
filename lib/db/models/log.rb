module Mobius
  class Database
    class Log < Sequel::Model
      plugin :timestamps
    end
  end
end
