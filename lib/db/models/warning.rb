module Mobius
  class Database
    class Warning < Sequel::Model
      plugin :timestamps, update_on_create: true
    end
  end
end
