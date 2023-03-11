module Mobius
  class Database
    class PluginData < Sequel::Model(:plugin_data)
      plugin :timestamps
    end
  end
end
