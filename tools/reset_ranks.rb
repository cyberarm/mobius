# Authored: 2023-09-10 by cyberarm

puts "#####################################################"
puts "# WARNING: This will DELETE any existing Rank data! #"
puts "#---------------------------------------------------#"
puts "# Enter: 'OK' without quotes to proceed.            #"
puts "#####################################################"
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

# NUKE ALL PLAYER RANKS
Mobius::Database::Rank.all.each do |record|
  record.delete # not efficient, but works.
end

Mobius::Database.teardown
Mobius::Config.teardown

puts
