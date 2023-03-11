module Mobius
  class Database
    class PluginData < Sequel::Model(:plugin_data)
      plugin :timestamps, update_on_create: true
    end
  end
end
