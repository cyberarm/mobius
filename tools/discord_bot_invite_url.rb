require "json"
require "discordrb"

config = JSON.parse(File.read("conf/config.json"), symbolize_names: true)
token = config.dig(:mobius, :discord_bot, :token)

raise "Discord Bot TOKEN is missing!" unless token

bot = Discordrb::Bot.new(token: token)

puts bot.invite_url
