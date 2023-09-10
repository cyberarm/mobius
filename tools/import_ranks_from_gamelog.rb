# Authored: 2023-05-12 by cyberarm

puts "########################################################"
puts "# WARNING: This will OVERWRITE any existing Rank data! #"
puts "#------------------------------------------------------#"
puts "# Enter: 'OK' without quotes to proceed.               #"
puts "########################################################"
print "> "
input = gets.chomp
if input == "OK"
  puts "Processing..."
else
  puts "\"#{input}\" != \"OK\", aborting..."
  puts
  exit
end

MOBIUS_NO_INIT = true
require_relative "../mobius"
Mobius::Config.init
Mobius::Database.init

ranks_data = JSON.parse(File.read(ARGV.first), symbolize_names: true)

ranks_data.each do |player|
  rank = Mobius::Database::Rank.first(name: player[:name].downcase) || Mobius::Database::Rank.new(name: player[:name].downcase)

  rank.skill = player[:elo]

  rank.stats_total_matches = player[:matches]
  rank.stats_total_matches = player[:matches]
  rank.stats_matches_won = player[:matches_won]
  rank.stats_matches_lost = player[:matches_lost]
  rank.stats_score = player[:data][:stats_score]
  rank.stats_kills = player[:data][:stats_kills]
  rank.stats_deaths = player[:data][:stats_deaths]
  rank.stats_damage = player[:data][:stats_damage]
  rank.stats_healed = player[:data][:stats_healed]
  rank.stats_buildings_destroyed = player[:data][:stats_buildings_destroyed]
  rank.stats_building_repairs = player[:data][:stats_building_repairs]
  rank.stats_building_damage = player[:data][:stats_building_damage]
  rank.stats_vehicles_lost = player[:data][:stats_vehicles_lost]
  rank.stats_vehicles_destroyed = player[:data][:stats_vehicles_destroyed]
  rank.stats_vehicle_repairs = player[:data][:stats_vehicle_repairs]
  rank.stats_vehicle_damage = player[:data][:stats_vehicle_damage]
  rank.stats_vehicles_captured = player[:data][:stats_vehicles_captured]
  rank.stats_vehicles_stolen = player[:data][:stats_vehicles_stolen]

  unless rank.save
    pp rank

    exit(1)
  end
end

Mobius::Database.teardown
Mobius::Config.teardown

puts
