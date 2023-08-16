module Mobius
  class Database
    class ModeratorAction < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
