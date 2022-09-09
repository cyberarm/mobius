require "sinatra/base"
require "slim"
require "sassc"

module Mobius
  class ModerationToolApp < Sinatra::Base
    CONNECTIONS = []

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

    get "/mobius/stream?", provides: "text/event-stream" do
      stream :keep_open do |out|
        CONNECTIONS << out

        until out.closed?
          out << 'data: {"type":"keep_alive"}'
          out << "\n\n"

          sleep 1
        end

        out.callback { CONNECTIONS.delete(out) }
      end
    end

    get "/mobius/stream?" do
      pp request
    end

    post "/mobius/chat?" do
    end

    post "/mobius/fds?" do
    end

    get "/css/application.css?" do
      sass :application
    end
  end
end

Mobius::ModerationToolApp.run! if __FILE__ == $0
