require "json"
require "discordrb"

raise "DiscordBot plugin config file not found" unless File.exist?("plugins/configs/discord_bot.json")

config = JSON.parse(File.read("plugins/configs/discord_bot.json"), symbolize_names: true)
token = config[:token]

raise "Discord Bot TOKEN is missing!" unless token

bot = Discordrb::Bot.new(token: token)

puts bot.invite_url
puts
