module Mobius
  class ServerConfig
    @data = {}
    @installed_maps = []

    def self.fetch_available_maps
      RenRem.cmd("listgamedefs", 2)
    end

    def self.installed_maps
      @installed_maps
    end

    def self.scripts_version
      @data[:scripts_version]
    end

    def self.scripts_version=(string)
      @data[:scripts_version] = string
    end

    def self.scripts_revision
      @data[:scripts_revision]
    end

    def self.scripts_revision=(string)
      @data[:scripts_revision] = string
    end

    def self.force_bhs_dll_map
      @data[:force_bhs_dll_map]
    end

    # No Op?
    def self.force_bhs_dll_map=(bool)
      @data[:force_bhs_dll_map] = bool
    end
  end
end
