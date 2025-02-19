require "json"
require "socket"
require "resolv"
require "fileutils"

# require "lmdb"
require "sequel"
require "sequel/core"
require "sqlite3"
require "excon"
require "ld-eventsource"
require "bcrypt"
require "discordrb"
require "perlin_noise"
require "openssl"
require "ircparser"
require "zip"

require_relative "lib/data_recorder"
require_relative "lib/common"
require_relative "lib/constants"
require_relative "lib/log"
require_relative "lib/config"
require_relative "lib/color"
require_relative "lib/teams"
require_relative "lib/server_config"
require_relative "lib/plugin_manager"
require_relative "lib/plugin"
require_relative "lib/renrem"
require_relative "lib/ssgm"
require_relative "lib/presets"
require_relative "lib/gamelog"
require_relative "lib/renlog"
require_relative "lib/database"
require_relative "lib/player_data"
require_relative "lib/server_status"
require_relative "lib/map_settings"
require_relative "lib/moderation_server_client"
require_relative "lib/init"
require_relative "lib/version"

def monotonic_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

Dir.chdir(__dir__)

Mobius.init unless defined?(MOBIUS_NO_INIT)
