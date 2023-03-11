module Mobius
  class Database
    class Ban < Sequel::Model
      plugin :timestamps
    end
  end
end
