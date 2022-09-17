module Mobius
  class ModerationServerClient
    @sse_client = nil
    @server = Excon.new("http://localhost:32068/mobius/ingest", persistent: true)

    def self.init
      log "INIT", "Enabling ModerationServerClient..."
      @running = true

      monitor
    end

    def self.running?
      @running
    end

    def self.teardown
      log "TEARDOWN", "Shutdown ModerationServerClient..."
      @sse_client&.close
    end

    def self.monitor
      Thread.new do
        post(:full_payload)

        @sse_client = SSE::Client.new("http://localhost:32068/mobius/deliveries") do |client|
          client.on_event do |event|
            handle_payload(JSON.parse(event.data, symbolize_names: true))
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

      tries = 0
      begin
        response = @server.post(body: json)
        case response.status
        when 200
        when 401
          log "Misconfigured Agent, got 401..."
        else
          log "Something went wrong: #{response.status}"
        end

      rescue Errno::ECONNRESET, Errno::ECONNABORTED, Excon::Error::Socket
        tries += 1

        if tries > 5
          puts "FAILED TO DELIVER PAYLOAD: #{json}"
        else
          retry
        end
      end
    end

    def self.handle_payload(payload)
      case payload[:type]
      when "chat"
        log "ModerationServerClient", "CHAT: #{payload[:message]}"
        # TODO: Inject this as a normal chat message so that commands are parsed
        RenRem.cmd("msg [MOBIUS+REMOTE] #{payload[:message][0..210]}")
      when "fds"
        log "ModerationServerClient", "FDS: #{payload[:message]}"
        RenRem.cmd(payload[:message])
      when "keep_alive"
        # NO OP
      else
        log "ModerationServerClient", "UNHANDLED PAYLOAD: #{payload}"
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
        teams: Teams.list,
        players: players,
        map: ServerStatus.get(:current_map)
      }.to_json
    end
  end
end
