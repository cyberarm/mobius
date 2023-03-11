module Mobius
  class Database
    class Kick < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
