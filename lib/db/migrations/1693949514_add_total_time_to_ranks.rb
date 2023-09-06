Sequel.migration do
  change do
    add_column :ranks, :stats_total_time, Float, default: 0
  end
end
