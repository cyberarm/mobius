module Mobius
  class Database
    class IP < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
