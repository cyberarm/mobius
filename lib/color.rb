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
  end
end
