module Mobius
  class Database
    class Recommendation < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
