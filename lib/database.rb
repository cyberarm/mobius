module Mobius
  class Database
    def self.init
      log "INIT", "Connecting to Database..."

      # @env = LMDB.new(Config.database_path)
      @db = SQLite3::Database.new(Config.database_path)

      create_default_tables!
    end

    def self.execute(query)
      @db.execute(query)
    end

    def self.transaction(&block)
      @db.transaction do
        block&.call
      end
    end

    def self.create_default_tables!
      transaction do
        # Authed Users
        execute <<-SQL
          create table if not exists auth_users (
            id integer primary key autoincrement,
            name text unique,
            password text
          );
        SQL

        # Bans
        execute <<-SQL
          create table if not exists bans (
            id integer primary key autoincrement,
            name text,
            ip text,
            serial text,
            banner text,
            reason text,
            timestamp integer
          );
        SQL

        # Kicks
        execute <<-SQL
          create table if not exists kicks (
            id integer primary key autoincrement,
            name text,
            ip text,
            serial text,
            banner text,
            reason text,
            timestamp integer
          );
        SQL

        # Plugins
        execute <<-SQL
          create table if not exists auth_users (
            name integer primary key,
            enabled integer
          );
        SQL
      end
    end

    def self.teardown
      log "TEARDOWN", "Closing Database..."
    end
  end
end
