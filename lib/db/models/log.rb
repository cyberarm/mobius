module Mobius
  class Database
    class Log < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
