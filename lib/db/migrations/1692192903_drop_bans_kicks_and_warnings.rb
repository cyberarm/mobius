Sequel.migration do
  change do
    drop_table(:bans, :kicks, :warnings)
  end
end