module Mobius
  class Database
    class RecommendationCounterCache < Sequel::Model(:recommendation_counter_cache)
      plugin :timestamps, update_on_create: true
    end
  end
end
