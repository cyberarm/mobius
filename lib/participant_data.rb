module Mobius
  class ParticipantData
    PROTOCOL_VERSION = 1
    BOTCOUNT_CONFIRM_DELAY = 1.0
    BOTCOUNT_PENDING_TIMEOUT = 30.0
    STATUS_KEYS = %i[
      native_enabled configured target_total_population target_team
      requested_bots_total requested_bots_team0 requested_bots_team1
      actual_bots_team0 actual_bots_team1
    ].freeze

    Participant = Struct.new(:id, :kind, :team, :score, keyword_init: true) do
      def human? = kind == :human
      def bot? = kind == :bot
    end

    Snapshot = Struct.new(:version, :status, :participants, :generation, keyword_init: true) do
      def native_enabled? = status[:native_enabled]
      def configured? = status[:configured]

      def actual_bot_count(team = nil)
        return status[:actual_bots_team0] + status[:actual_bots_team1] if team.nil?
        return status[:actual_bots_team0] if team == 0
        return status[:actual_bots_team1] if team == 1

        raise ArgumentError, "team must be 0, 1, or nil"
      end

      def requested_bot_count(team = nil)
        return status[:requested_bots_total] if team.nil?
        return status[:requested_bots_team0] if team == 0
        return status[:requested_bots_team1] if team == 1

        raise ArgumentError, "team must be 0, 1, or nil"
      end
    end

    @supported = nil
    @snapshot = nil
    @last_error = nil
    @generation = 0
    @request_epoch = 0
    @population_pending_until = nil
    @mutex = Mutex.new

    class << self
      def refresh
        request_epoch = @mutex.synchronize do
          next if @supported == false
          next if population_change_pending_locked?

          @request_epoch
        end
        return if request_epoch.nil?

        queue_refresh(request_epoch)
      end

      def set_bot_population(count, team: nil)
        target = count.to_i.clamp(0, 300)
        target_team = team.nil? ? 2 : team.to_i
        target_team = 2 unless (0..2).cover?(target_team)
        command = "botcount #{target}"
        command += " #{target_team}" unless team.nil?

        request_epoch = @mutex.synchronize do
          invalidate_snapshot_locked
          @population_pending_until = monotonic_now + BOTCOUNT_PENDING_TIMEOUT
          publish_provisional_counts(target, target_team)
          @request_epoch
        end

        RenRem.cmd(command) do
          queue_refresh(
            request_epoch,
            delay: BOTCOUNT_CONFIRM_DELAY,
            clear_population_pending: true
          )
        end
      end

      def update_from_response(response, expected_epoch: nil)
        lines = response.to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
        return false if lines.empty?

        if lines.any? { |line| line.match?(/\Aparticipant_info not found\z/i) }
          @mutex.synchronize do
            return false if stale_request?(expected_epoch)

            clear_native_counts_locked
            @supported = false
            @snapshot = nil
            @last_error = "participant_info command is unavailable"
          end
          return false
        end

        if (error = lines.find { |line| line.start_with?("PARTICIPANT_INFO_ERROR,") })
          @mutex.synchronize do
            return false if stale_request?(expected_epoch)

            @supported = true
            @last_error = error
          end
          return false
        end

        parsed = parse_snapshot(lines)
        @mutex.synchronize do
          return false if stale_request?(expected_epoch)

          @supported = true
          @generation += 1
          parsed.generation = @generation
          parsed.freeze
          @snapshot = parsed
          @last_error = nil
          publish_counts(parsed)
        end
        true
      rescue ArgumentError => e
        @mutex.synchronize do
          @last_error = e.message unless stale_request?(expected_epoch)
        end
        false
      end

      def snapshot = @mutex.synchronize { @snapshot }
      def last_error = @mutex.synchronize { @last_error }
      def supported? = @mutex.synchronize { @supported == true }
      def unsupported? = @mutex.synchronize { @supported == false }
      def available? = !snapshot.nil?
      def native_enabled? = snapshot&.native_enabled? || false
      def configured? = snapshot&.configured? || false
      def status = snapshot&.status
      def target_total_population = snapshot&.status&.dig(:target_total_population)
      def target_team = snapshot&.status&.dig(:target_team)

      def participants(kind: nil, team: nil)
        current = snapshot
        result = current ? current.participants : []
        result = result.select { |participant| participant.kind == kind.to_sym } if kind
        result = result.select { |participant| participant.team == team } unless team.nil?
        result.dup
      end

      def humans(team: nil) = participants(kind: :human, team: team)
      def bots(team: nil) = participants(kind: :bot, team: team)

      def actual_bot_count(team = nil)
        current = snapshot
        current.actual_bot_count(team) if current&.native_enabled?
      end

      def requested_bot_count(team = nil)
        current = snapshot
        current.requested_bot_count(team) if current&.native_enabled?
      end

      # Participant IDs are map-scoped. Keep feature detection, but discard IDs.
      def clear
        @mutex.synchronize do
          clear_native_counts_locked
          invalidate_snapshot_locked
          @population_pending_until = nil
        end
      end

      def reset!
        @mutex.synchronize do
          clear_bot_counts_locked
          @supported = nil
          @snapshot = nil
          @last_error = nil
          @population_pending_until = nil
          @request_epoch += 1
        end
      end

      private

      def queue_refresh(request_epoch, delay: nil, clear_population_pending: false)
        should_queue = @mutex.synchronize do
          next false if stale_request?(request_epoch)

          if @supported == false
            @population_pending_until = nil if clear_population_pending
            next false
          end
          true
        end
        return unless should_queue

        RenRem.cmd("participant_info #{PROTOCOL_VERSION}", delay) do |response|
          begin
            update_from_response(response, expected_epoch: request_epoch)
          ensure
            @mutex.synchronize do
              if clear_population_pending && !stale_request?(request_epoch)
                @population_pending_until = nil
              end
            end
          end
        end
      end

      def invalidate_snapshot_locked
        had_snapshot = !@snapshot.nil?
        @snapshot = nil
        @last_error = nil
        @generation += 1 if had_snapshot
        @request_epoch += 1
      end

      def population_change_pending_locked?
        return false unless @population_pending_until
        if monotonic_now >= @population_pending_until
          @population_pending_until = nil
          return false
        end
        true
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def stale_request?(expected_epoch)
        !expected_epoch.nil? && expected_epoch != @request_epoch
      end

      def parse_snapshot(lines)
        begins = lines.each_index.select { |index| lines[index].start_with?("PARTICIPANT_INFO_BEGIN,") }
        ends = lines.each_index.select { |index| lines[index].start_with?("PARTICIPANT_INFO_END,") }
        raise ArgumentError, "participant_info response must contain one begin and one end record" unless begins.size == 1 && ends.size == 1

        first = begins.first
        last = ends.first
        raise ArgumentError, "participant_info end record preceded its begin record" unless last > first

        begin_fields = fields(lines[first], "PARTICIPANT_INFO_BEGIN")
        end_fields = fields(lines[last], "PARTICIPANT_INFO_END")
        version = integer(begin_fields[:version], :version)
        raise ArgumentError, "unsupported participant_info version #{version}" unless version == PROTOCOL_VERSION
        raise ArgumentError, "participant_info begin/end versions did not match" unless integer(end_fields[:version], :version) == version

        body = lines[(first + 1)...last]
        status_lines = body.select { |line| line.start_with?("PARTICIPANT_INFO_STATUS,") }
        raise ArgumentError, "participant_info response must contain exactly one status record" unless status_lines.size == 1

        parsed_status = parse_status(fields(status_lines.first, "PARTICIPANT_INFO_STATUS"))
        parsed_participants = {}
        body.grep(/\APARTICIPANT_INFO_ROW,/).each do |line|
          participant = parse_participant(fields(line, "PARTICIPANT_INFO_ROW"))
          raise ArgumentError, "duplicate participant_info id #{participant.id}" if parsed_participants.key?(participant.id)
          parsed_participants[participant.id] = participant.freeze
        end

        declared_rows = integer(end_fields[:rows], :rows)
        raise ArgumentError, "participant_info declared #{declared_rows} rows but received #{parsed_participants.size}" unless declared_rows == parsed_participants.size

        Snapshot.new(
          version: version,
          status: parsed_status.freeze,
          participants: parsed_participants.values.freeze,
          generation: nil
        )
      end

      def fields(line, expected)
        parts = line.split(",")
        record = parts.shift
        raise ArgumentError, "expected #{expected}, received #{record}" unless record == expected

        parts.each_with_object({}) do |part, result|
          key, value = part.split("=", 2)
          raise ArgumentError, "malformed #{expected} field #{part}" if key.to_s.empty? || value.nil?
          key = key.to_sym
          raise ArgumentError, "duplicate #{expected} field #{key}" if result.key?(key)
          result[key] = value
        end
      end

      def parse_status(data)
        missing = STATUS_KEYS - data.keys
        raise ArgumentError, "participant_info status missing #{missing.join(', ')}" unless missing.empty?

        {
          native_enabled: boolean(data[:native_enabled], :native_enabled),
          configured: boolean(data[:configured], :configured),
          target_total_population: integer(data[:target_total_population], :target_total_population),
          target_team: integer(data[:target_team], :target_team),
          requested_bots_total: integer(data[:requested_bots_total], :requested_bots_total),
          requested_bots_team0: integer(data[:requested_bots_team0], :requested_bots_team0),
          requested_bots_team1: integer(data[:requested_bots_team1], :requested_bots_team1),
          actual_bots_team0: integer(data[:actual_bots_team0], :actual_bots_team0),
          actual_bots_team1: integer(data[:actual_bots_team1], :actual_bots_team1)
        }
      end

      def parse_participant(data)
        missing = %i[id kind team score] - data.keys
        raise ArgumentError, "participant_info row missing #{missing.join(', ')}" unless missing.empty?
        kind = data[:kind].to_sym
        raise ArgumentError, "invalid participant kind #{data[:kind]}" unless %i[human bot].include?(kind)

        score = begin
          Float(data[:score])
        rescue ArgumentError, TypeError
          raise ArgumentError, "invalid participant_info score #{data[:score]}"
        end

        Participant.new(id: integer(data[:id], :id), kind: kind,
                        team: integer(data[:team], :team), score: score)
      end

      def integer(value, name)
        Integer(value, 10)
      rescue ArgumentError, TypeError
        raise ArgumentError, "invalid participant_info #{name} #{value}"
      end

      def boolean(value, name)
        return false if value == "0"
        return true if value == "1"
        raise ArgumentError, "invalid participant_info #{name} #{value}"
      end

      def publish_counts(parsed)
        return unless defined?(PluginManager)
        if parsed.native_enabled?
          PluginManager.blackboard_store(:team_0_bot_count, parsed.actual_bot_count(0))
          PluginManager.blackboard_store(:team_1_bot_count, parsed.actual_bot_count(1))
        end
      end

      def publish_provisional_counts(target, team)
        return unless defined?(PluginManager)

        humans = [0, 0]
        if defined?(PlayerData)
          humans[0] = PlayerData.players_by_team(0).to_a.size
          humans[1] = PlayerData.players_by_team(1).to_a.size
        end

        requested = [0, 0]
        if team == 0 || team == 1
          requested[team] = [target - humans[team], 0].max
        else
          requested[0] = [(target + 1) / 2 - humans[0], 0].max
          requested[1] = [target / 2 - humans[1], 0].max
        end

        PluginManager.blackboard_store(:team_0_bot_count, requested[0])
        PluginManager.blackboard_store(:team_1_bot_count, requested[1])
      end

      def clear_native_counts_locked
        clear_bot_counts_locked if @snapshot&.native_enabled?
      end

      def clear_bot_counts_locked
        return unless defined?(PluginManager)

        PluginManager.blackboard_store(:team_0_bot_count, 0)
        PluginManager.blackboard_store(:team_1_bot_count, 0)
      end
    end
  end
end
