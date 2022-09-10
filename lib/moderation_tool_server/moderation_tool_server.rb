require "sinatra/base"
require "slim"
require "sassc"

module Mobius
  class ModerationToolApp < Sinatra::Base
    CLIENTS = []
    BOTS = []

    configure do
      set port: 32_068
      set root: File.expand_path(".", __dir__)
      set server: :puma
      set :logging, false
    end

    get "/?" do
      slim :sign_in
    end

    post "/sign_in?" do
      redirect "/mobius"
    end

    get "/sign_out?" do
      redirect "/"
    end

    get "/mobius?" do
      slim :mobius
    end

    # FOR FRONTEND

    get "/mobius/stream?", provides: "text/event-stream" do
      stream :keep_open do |out|
        CLIENTS << out

        until out.closed?
          out << 'data: {"type":"keep_alive"}'
          out << "\n\n"

          sleep 1
        end

        out.callback { CLIENTS.delete(out) }
      end
    end

    post "/mobius/chat?" do
    end

    post "/mobius/fds?" do
    end

    # FOR MOBIUS BOT

    get "/mobius/deliveries?", provides: "text/event-stream" do
      stream :keep_open do |out|
        BOTS << out

        until out.closed?
          out << 'data: {"type":"keep_alive"}'
          out << "\n\n"

          sleep 1
        end

        out.callback { BOTS.delete(out) }
      end
    end

    post "/mobius/ingest?" do
      # TODO: Check for authorization header
      # TODO: Check which server this bot is serving
      payload = request.body.read
      pp payload

      CLIENTS.each do |c|
        begin
          c << request.body.read
          c << "\n\n"
        rescue => e
          pp e
          pp e.backtrace
        end
      end

      "OKAY"
    end

    get "/css/application.css?" do
      sass :application
    end
  end
end

Mobius::ModerationToolApp.run! if __FILE__ == $0
