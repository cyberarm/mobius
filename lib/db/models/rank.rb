module Mobius
  class Database
    class Rank < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
