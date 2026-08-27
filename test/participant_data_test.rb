require "minitest/autorun"
require_relative "../lib/participant_data"

module Mobius
  class PluginManager
    @blackboard = {}

    class << self
      attr_reader :blackboard

      def reset_test_state
        @blackboard = {}
      end

      def blackboard_store(key, value)
        @blackboard[key] = value
      end
    end
  end

  class PlayerData
    class << self
      def reset_test_state
        @team_counts = [0, 0]
      end

      def set_team_counts(team_zero, team_one)
        @team_counts = [team_zero, team_one]
      end

      def players_by_team(team)
        Array.new(@team_counts.fetch(team), Object.new)
      end
    end
  end

  class RenRem
    class << self
      attr_reader :commands

      def reset_test_state
        @commands = []
        @callbacks = []
      end

      def cmd(command, delay = nil, &block)
        @commands << [command, delay]
        @callbacks << block if block
      end

      def deliver_next(response)
        callback = @callbacks.shift
        callback&.call(response)
      end
    end
  end
end

class ParticipantDataTest < Minitest::Test
  def setup
    Mobius::PluginManager.reset_test_state
    Mobius::PlayerData.reset_test_state
    Mobius::ParticipantData.reset!
    Mobius::RenRem.reset_test_state
  end

  def valid_response(native_enabled: 1)
    <<~RESPONSE
      PARTICIPANT_INFO_BEGIN,version=1
      PARTICIPANT_INFO_STATUS,native_enabled=#{native_enabled},configured=1,target_total_population=3,target_team=2,requested_bots_total=1,requested_bots_team0=0,requested_bots_team1=1,actual_bots_team0=0,actual_bots_team1=1,future_field=accepted
      PARTICIPANT_INFO_ROW,id=7,kind=human,team=0,score=125.500000
      PARTICIPANT_INFO_FUTURE,value=ignored
      PARTICIPANT_INFO_ROW,id=-1001,kind=bot,team=1,score=300.000000
      PARTICIPANT_INFO_END,version=1,rows=2
    RESPONSE
  end

  def test_parses_a_complete_version_one_snapshot_atomically
    assert Mobius::ParticipantData.update_from_response(valid_response)

    assert Mobius::ParticipantData.supported?
    assert Mobius::ParticipantData.available?
    assert Mobius::ParticipantData.native_enabled?
    assert_equal 3, Mobius::ParticipantData.target_total_population
    assert_equal 2, Mobius::ParticipantData.target_team
    assert_equal [7], Mobius::ParticipantData.humans.map(&:id)
    assert_equal [-1001], Mobius::ParticipantData.bots.map(&:id)
    assert_in_delta 300.0, Mobius::ParticipantData.bots.first.score
    assert_equal 1, Mobius::ParticipantData.actual_bot_count
    assert_equal 1, Mobius::ParticipantData.requested_bot_count
    assert_equal 0, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 1, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_refresh_uses_the_versioned_command
    Mobius::ParticipantData.refresh
    Mobius::RenRem.deliver_next(valid_response)

    assert_equal ["participant_info 1", nil], Mobius::RenRem.commands.last
    assert Mobius::ParticipantData.available?
  end

  def test_bot_population_change_publishes_provisional_then_confirms
    assert Mobius::ParticipantData.update_from_response(valid_response)

    Mobius::ParticipantData.set_bot_population(4, team: 1)

    refute Mobius::ParticipantData.available?
    assert Mobius::ParticipantData.supported?
    assert_nil Mobius::ParticipantData.actual_bot_count
    assert_equal 0, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 4, Mobius::PluginManager.blackboard[:team_1_bot_count]
    assert_equal [["botcount 4 1", nil]], Mobius::RenRem.commands

    Mobius::ParticipantData.refresh
    assert_equal 1, Mobius::RenRem.commands.size

    Mobius::RenRem.deliver_next(nil)
    assert_equal ["participant_info 1", Mobius::ParticipantData::BOTCOUNT_CONFIRM_DELAY],
                 Mobius::RenRem.commands.last

    Mobius::RenRem.deliver_next(valid_response)
    assert Mobius::ParticipantData.available?
    assert_equal 1, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_provisional_counts_match_engine_target_population_rules
    Mobius::PlayerData.set_team_counts(2, 1)

    Mobius::ParticipantData.set_bot_population(6)

    assert_equal 1, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 2, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_legacy_server_still_receives_botcount_without_future_probes
    refute Mobius::ParticipantData.update_from_response("participant_info not found")

    Mobius::ParticipantData.set_bot_population(4)
    Mobius::RenRem.deliver_next(nil)

    assert_equal [["botcount 4", nil]], Mobius::RenRem.commands
    assert_equal 2, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 2, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_map_clear_rejects_an_in_flight_snapshot
    Mobius::ParticipantData.refresh
    Mobius::ParticipantData.clear

    Mobius::RenRem.deliver_next(valid_response)

    refute Mobius::ParticipantData.available?
    refute Mobius::ParticipantData.supported?
    assert_equal 0, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 0, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_server_reset_rejects_an_in_flight_snapshot
    Mobius::ParticipantData.refresh
    Mobius::ParticipantData.reset!

    Mobius::RenRem.deliver_next(valid_response)

    refute Mobius::ParticipantData.available?
    refute Mobius::ParticipantData.supported?
    assert_equal 0, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 0, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end

  def test_malformed_snapshot_does_not_replace_last_good_snapshot
    assert Mobius::ParticipantData.update_from_response(valid_response)
    original = Mobius::ParticipantData.snapshot

    refute Mobius::ParticipantData.update_from_response(valid_response.sub("rows=2", "rows=3"))

    assert_same original, Mobius::ParticipantData.snapshot
    assert_match(/declared 3 rows/, Mobius::ParticipantData.last_error)
  end

  def test_duplicate_participant_ids_are_rejected
    duplicate = valid_response.sub(
      "PARTICIPANT_INFO_END,version=1,rows=2",
      "PARTICIPANT_INFO_ROW,id=-1001,kind=bot,team=1,score=1.0\nPARTICIPANT_INFO_END,version=1,rows=3"
    )

    refute Mobius::ParticipantData.update_from_response(duplicate)
    assert_match(/duplicate participant_info id -1001/, Mobius::ParticipantData.last_error)
  end

  def test_begin_and_end_versions_must_match
    mismatch = valid_response.sub(
      "PARTICIPANT_INFO_END,version=1",
      "PARTICIPANT_INFO_END,version=2"
    )

    refute Mobius::ParticipantData.update_from_response(mismatch)
    assert_match(/versions did not match/, Mobius::ParticipantData.last_error)
  end

  def test_old_server_marks_command_unsupported_and_discards_map_ids
    assert Mobius::ParticipantData.update_from_response(valid_response)

    refute Mobius::ParticipantData.update_from_response("participant_info not found")

    assert Mobius::ParticipantData.unsupported?
    refute Mobius::ParticipantData.available?
    assert_match(/unavailable/, Mobius::ParticipantData.last_error)
  end

  def test_protocol_error_retains_the_last_good_snapshot
    assert Mobius::ParticipantData.update_from_response(valid_response)
    original = Mobius::ParticipantData.snapshot

    refute Mobius::ParticipantData.update_from_response(
      "PARTICIPANT_INFO_ERROR,code=unsupported_version,requested=2,supported=1"
    )

    assert_same original, Mobius::ParticipantData.snapshot
  end

  def test_disabled_native_bots_do_not_overwrite_legacy_estimates
    Mobius::PluginManager.blackboard_store(:team_0_bot_count, 4)
    Mobius::PluginManager.blackboard_store(:team_1_bot_count, 5)

    assert Mobius::ParticipantData.update_from_response(valid_response(native_enabled: 0))

    assert_equal 4, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 5, Mobius::PluginManager.blackboard[:team_1_bot_count]
    assert_nil Mobius::ParticipantData.actual_bot_count
  end

  def test_clear_discards_map_scoped_ids_but_preserves_feature_detection
    assert Mobius::ParticipantData.update_from_response(valid_response)

    Mobius::ParticipantData.clear

    assert Mobius::ParticipantData.supported?
    refute Mobius::ParticipantData.available?
    assert_empty Mobius::ParticipantData.participants
    assert_equal 0, Mobius::PluginManager.blackboard[:team_0_bot_count]
    assert_equal 0, Mobius::PluginManager.blackboard[:team_1_bot_count]
  end
end
