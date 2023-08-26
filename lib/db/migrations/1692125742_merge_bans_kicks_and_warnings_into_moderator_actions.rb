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
          action: Mobius::MODERATOR_ACTION[:ban],
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
          action: Mobius::MODERATOR_ACTION[:kick],
          created_at: kick.created_at,
          updated_at: kick.updated_at
        )
      end
    end
  end
end