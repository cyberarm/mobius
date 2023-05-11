Sequel.migration do
  change do
    create_table(:ranks) do
      primary_key :id
      String :name, null: false

      Integer :rank, default: 0
      Float   :skill, default: 0.0
      Float   :confidence, default: 25.0

      Integer :stats_total_matches, default: 0
      Integer :stats_matches_won, default: 0
      Integer :stats_matches_lost, default: 0
      Integer :stats_score, default: 0
      Integer :stats_kills, default: 0
      Integer :stats_deaths, default: 0
      Float   :stats_damage, default: 0.0
      Integer :stats_healed, default: 0
      Integer :stats_buildings_destroyed, default: 0
      Integer :stats_building_repairs, default: 0
      Float   :stats_building_damage, default: 0.0
      Integer :stats_vehicles_lost, default: 0
      Integer :stats_vehicles_destroyed, default: 0
      Integer :stats_vehicle_repairs, default: 0
      Float   :stats_vehicle_damage, default: 0.0
      Integer :stats_vehicles_captured, default: 0
      Integer :stats_vehicles_stolen, default: 0

      Time :created_at
      Time :updated_at

      index :name
    end
  end
end
