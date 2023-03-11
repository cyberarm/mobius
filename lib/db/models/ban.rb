module Mobius
  class Database
    class Ban < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
