Sequel.migration do
  up do
    if Mobius::Database.const_defined?(:Ban)
      Mobius::Database::Ban.all.each do |ban|
        Mobius::Database::ModeratorAction.create(
          name: ban.name,
          ip: ban.ip,
          serial: ban.serial,
          moderator: ban.banner,
          reason: ban.reason,
          action: Mobius::MODERATOR_ACION[:ban],
          created_at: ban.created_at,
          updated_at: ban.updated_at
        )
      end
    end

    if Mobius::Database.const_defined?(:Kick)
      Mobius::Database::Kick.all.each do |kick|
        Mobius::Database::ModeratorAction.create(
          name: kick.name,
          ip: kick.ip,
          serial: kick.serial,
          moderator: kick.banner,
          reason: kick.reason,
          action: Mobius::MODERATOR_ACION[:kick],
          created_at: kick.created_at,
          updated_at: kick.updated_at
        )
      end
    end

    if Mobius::Database.const_defined?(:Warning)
      Mobius::Database::Warning.all.each do |warning|
        Mobius::Database::ModeratorAction.create(
          name: warning.name,
          ip: warning.ip,
          serial: warning.serial,
          moderator: warning.banner,
          reason: warning.reason,
          action: Mobius::MODERATOR_ACION[:warning],
          created_at: warning.created_at,
          updated_at: warning.updated_at
        )
      end
    end
  end
end