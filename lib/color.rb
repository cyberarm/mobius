module Mobius
  class Color
    attr_reader :red, :green, :blue

    # Accepts an RGB hex color OR 255,255,255 red, green, and blue values
    def initialize(hex_color = nil, red: -1, green: -1, blue: -1)
      if hex_color
        @red = hex_color >> 16
        @green = hex_color >> 8
        @blue = hex_color >> 0
      else
        @red = red.to_i
        @green = green.to_i
        @blue = blue.to_i
      end

      @red %= 256
      @green %= 256
      @blue %= 256
    end

    # TODO: generate irc-safe color(s) from rgb color
    def irc
    end

    def to_h
      {
        red: @red,
        green: @green,
        blue: @blue
      }
    end

    def to_a
      [@red, @green, @blue]
    end

    # From: https://modern.ircdocs.horse/formatting.html#colors
    IRC_COLORS = {
      # Generally guaranteed to be supported IRC colors
      "00" => Color.new(0xffffff), # White
      "01" => Color.new(0x000000), # Black
      "02" => Color.new(0x00007f), # Blue
      "03" => Color.new(0x009300), # Green
      "04" => Color.new(0xff0000), # Red
      "05" => Color.new(0x7f0000), # Brown
      "06" => Color.new(0x9c009c), # Megenta
      "07" => Color.new(0xfc7f00), # Orange
      "08" => Color.new(0xffff00), # Yellow
      "09" => Color.new(0x00fc00), # Light Green
      "10" => Color.new(0x009393), # Cyan
      "11" => Color.new(0x00ffff), # Light Cyan
      "12" => Color.new(0x0000fc), # Light Blue
      "13" => Color.new(0xff00ff), # Pink
      "14" => Color.new(0x7f7f7f), # Gray
      "15" => Color.new(0xd2d2d2), # Light Gray

      # Probably supported IRC colors
      "16" => Color.new(0x470000),
      "17" => Color.new(0x472100),
      "18" => Color.new(0x474700),
      "19" => Color.new(0x324700),
      "20" => Color.new(0x004700),
      "21" => Color.new(0x00472c),
      "22" => Color.new(0x004747),
      "23" => Color.new(0x002747),
      "24" => Color.new(0x000047),
      "25" => Color.new(0x2e0047),
      "26" => Color.new(0x470047),
      "27" => Color.new(0x47002a),
      "28" => Color.new(0x740000),
      "29" => Color.new(0x743a00),
      "30" => Color.new(0x747400),
      "31" => Color.new(0x517400),
      "32" => Color.new(0x007400),
      "33" => Color.new(0x007449),
      "34" => Color.new(0x007474),
      "35" => Color.new(0x004074),
      "36" => Color.new(0x000074),
      "37" => Color.new(0x4b0074),
      "38" => Color.new(0x740074),
      "39" => Color.new(0x740045),
      "40" => Color.new(0xb50000),
      "41" => Color.new(0xb56300),
      "42" => Color.new(0xb5b500),
      "43" => Color.new(0x7db500),
      "44" => Color.new(0x00b500),
      "45" => Color.new(0x00b571),
      "46" => Color.new(0x00b5b5),
      "47" => Color.new(0x0063b5),
      "48" => Color.new(0x0000b5),
      "49" => Color.new(0x7500b5),
      "50" => Color.new(0xb500b5),
      "51" => Color.new(0xb5006b),
      "52" => Color.new(0xff0000),
      "53" => Color.new(0xff8c00),
      "54" => Color.new(0xffff00),
      "55" => Color.new(0xb2ff00),
      "56" => Color.new(0x00ff00),
      "57" => Color.new(0x00ffa0),
      "58" => Color.new(0x00ffff),
      "59" => Color.new(0x008cff),
      "60" => Color.new(0x0000ff),
      "61" => Color.new(0xa500ff),
      "62" => Color.new(0xff00ff),
      "63" => Color.new(0xff0098),
      "64" => Color.new(0xff5959),
      "65" => Color.new(0xffb459),
      "66" => Color.new(0xffff71),
      "67" => Color.new(0xcfff60),
      "68" => Color.new(0x6fff6f),
      "69" => Color.new(0x65ffc9),
      "70" => Color.new(0x6dffff),
      "71" => Color.new(0x59b4ff),
      "72" => Color.new(0x5959ff),
      "73" => Color.new(0xc459ff),
      "74" => Color.new(0xff66ff),
      "75" => Color.new(0xff59bc),
      "76" => Color.new(0xff9c9c),
      "77" => Color.new(0xffd39c),
      "78" => Color.new(0xffff9c),
      "79" => Color.new(0xe2ff9c),
      "80" => Color.new(0x9cff9c),
      "81" => Color.new(0x9cffdb),
      "82" => Color.new(0x9cffff),
      "83" => Color.new(0x9cd3ff),
      "84" => Color.new(0x9c9cff),
      "85" => Color.new(0xdc9cff),
      "86" => Color.new(0xff9cff),
      "87" => Color.new(0xff94d3),
      "88" => Color.new(0x000000),
      "89" => Color.new(0x131313),
      "90" => Color.new(0x282828),
      "91" => Color.new(0x363636),
      "92" => Color.new(0x4d4d4d),
      "93" => Color.new(0x656565),
      "94" => Color.new(0x818181),
      "95" => Color.new(0x9f9f9f),
      "96" => Color.new(0xbcbcbc),
      "97" => Color.new(0xe2e2e2),
      "98" => Color.new(0xffffff),
    }.freeze

    # Cache closest hex to irc colors for future use
    IRC_COLOR_CACHE = {}

    def self.find_closest_irc_color(color)
      c = IRC_COLOR_CACHE[color]
      return c if c

      closest_match = "00"
      distance = Float::INFINITY

      IRC_COLORS.each do |key, irc_color|
        break if key == "16" # Limit colors to most supported.

        d = Math.sqrt(
          (color.red - irc_color.red)**2 +
          (color.green - irc_color.green)**2 +
          (color.blue - irc_color.blue)**2
        )

        if d < distance
          distance = d
          closest_match = key
        end
      end

      IRC_COLOR_CACHE[color] = closest_match

      closest_match
    end

    def self.irc_colorize(color, message)
      irc_color = find_closest_irc_color(color)

      format("\x03%s%s\x03", irc_color, message)
    end
  end
end
