require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "sassc"

module Mobius
  class ModerationToolApp < Sinatra::Base
    Client = Struct.new(:socket, :send_queue, :last_delivery, :keep_alive_interval)

    CLIENTS = []
    BOTS = []

    MEMORY = {}

    configure do
      set port: 32_068
      set root: File.expand_path(".", __dir__)
      set server: :puma
      set :logging, false
    end

    configure :development do
      register Sinatra::Reloader
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
        # CLIENTS << out
        client = Client.new(out, [], -1, 15)

        CLIENTS << client
        client.socket.callback { CLIENTS.delete(client) }

        until client.socket.closed?
          if client.send_queue.empty? && monotonic_time.to_i >= client.last_delivery + client.keep_alive_interval
            client.last_delivery = monotonic_time.to_i

            client.socket << 'data: {"type":"keep_alive"}'
            client.socket << "\n\n"
          else
            while (data = client.send_queue.shift)
              client.last_delivery = monotonic_time.to_i

              client.socket << "data: #{data}\n\n"
            end
          end

          sleep 1
        end
      end
    end

    post "/mobius/chat?" do
      payload = request.body.read
      hash = JSON.parse(payload, symbolize_names: true)

      case hash[:type]
      when "chat", "team_chat", "log"
        BOTS.each { |b| b.send_queue << payload }
      else
        pp hash
        halt 400
      end

      "OK"
    end

    post "/mobius/fds?" do
    end

    # FOR MOBIUS BOT

    get "/mobius/deliveries?", provides: "text/event-stream" do
      # TODO: Check for authorization header
      # TODO: Check which server this bot is serving

      stream :keep_open do |out|
        client = Client.new(out, [], -1, 15)

        BOTS << client
        client.socket.callback { BOTS.delete(client) }

        until client.socket.closed?
          if client.send_queue.empty? && monotonic_time.to_i >= client.last_delivery + client.keep_alive_interval
            client.last_delivery = monotonic_time.to_i

            client.socket << 'data: {"type":"keep_alive"}'
            client.socket << "\n\n"
          else
            while (data = client.send_queue.shift)
              client.last_delivery = monotonic_time.to_i

              client.socket << "data: #{data}\n\n"
            end
          end

          sleep 1
        end

        out.callback { BOTS.delete(out) }
      end
    end

    post "/mobius/ingest?" do
      # TODO: Check for authorization header
      # TODO: Check which server this bot is serving
      payload = request.body.read

      CLIENTS.each do |client|
        begin
          client.send_queue << payload
        rescue => e
          pp e
          pp e.backtrace
        end
      end

      "OKAY"
    end

    get "/css/application.css?" do
      content_type :css

      scss = SassC::Sass2Scss.convert(File.read("views/application.sass"))
      SassC::Engine.new(scss, style: :compressed).render
    end
  end
end

Mobius::ModerationToolApp.run! if __FILE__ == $0
