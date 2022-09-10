module Mobius
  class ModerationServerClient
    @sse_client = nil
    @server = Excon.new("http://localhost:32068/mobius/ingest", persistent: true)

    def self.init
      log "INIT", "Enabling ModerationServerClient..."
      @running = true

      monitor
    end

    def self.teardown
      log "TEARDOWN", "Shutdown ModerationServerClient..."
      @sse_client&.close
    end

    def self.monitor
      Thread.new do
        @sse_client = SSE::Client.new("http://localhost:32068/mobius/stream") do |client|
          client.on_event do |event|
            puts "I received an event: #{event.type}, #{event.data}"
          end
        end
      end
    end

    def self.post(json)
      if json.is_a?(Symbol)
        case json
        when :full_payload
          json = full_payload
        end
      end

      response = @server.post(body: json)
      case response.status
      when 200
      when 401
        log "Misconfigured Agent, got 401..."
      else
        log "Something went wrong: #{response.status}"
      end
    end

    def self.full_payload
      players = PlayerData.player_list.select { |ply| ply.ingame? }.map do |player|
        {
          id: player.id,
          name: player.name,
          join_time: player.join_time,
          score: player.score,
          team: player.team,
          ping: player.ping,
          address: player.address,
          kbps: player.kbps,
          time: player.time,
          last_updated: player.last_updated
        }
      end

      {
        type: :full_payload,
        players: players,
        map: ServerStatus.get(:current_map)
      }.to_json
    end
  end
end
