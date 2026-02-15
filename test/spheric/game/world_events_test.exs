defmodule Spheric.Game.WorldEventsTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{WorldEvents, Hiss}

  setup do
    WorldEvents.init()
    WorldEvents.clear()
    WorldEvents.init()
    Hiss.init()
    Hiss.clear_all()

    on_exit(fn ->
      WorldEvents.clear()
      Hiss.clear_all()
    end)

    :ok
  end

  describe "state/0" do
    test "returns initial state" do
      state = WorldEvents.state()
      assert state.active_event == nil
      assert state.event_start_tick == 0
      assert state.last_event_tick == 0
      assert state.event_history == []
    end
  end

  describe "active_event/0" do
    test "returns nil when no active event" do
      assert WorldEvents.active_event() == nil
    end

    test "returns event type when active" do
      WorldEvents.put_state(%{
        active_event: :hiss_surge,
        event_start_tick: 1000,
        last_event_tick: 0,
        event_history: []
      })

      assert WorldEvents.active_event() == :hiss_surge
    end
  end

  describe "active?/1" do
    test "returns false when no active event" do
      refute WorldEvents.active?(:hiss_surge)
    end

    test "returns true when matching event is active" do
      WorldEvents.put_state(%{
        active_event: :meteor_shower,
        event_start_tick: 1000,
        last_event_tick: 0,
        event_history: []
      })

      assert WorldEvents.active?(:meteor_shower)
      refute WorldEvents.active?(:hiss_surge)
    end
  end

  describe "history/0" do
    test "returns empty list initially" do
      assert WorldEvents.history() == []
    end

    test "returns event history" do
      WorldEvents.put_state(%{
        active_event: nil,
        event_start_tick: 0,
        last_event_tick: 1500,
        event_history: [{:hiss_surge, 1000}, {:meteor_shower, 500}]
      })

      history = WorldEvents.history()
      assert length(history) == 2
    end
  end

  describe "event_info/1" do
    test "returns info for known event types" do
      info = WorldEvents.event_info(:hiss_surge)
      assert info.name == "Hiss Surge"
      assert is_integer(info.color)

      info = WorldEvents.event_info(:meteor_shower)
      assert info.name == "Meteor Shower"

      info = WorldEvents.event_info(:resonance_cascade)
      assert info.name == "Resonance Cascade"

      info = WorldEvents.event_info(:entity_migration)
      assert info.name == "Entity Migration"
    end

    test "returns unknown for invalid event type" do
      info = WorldEvents.event_info(:nonexistent)
      assert info.name == "Unknown"
    end
  end

  describe "process_tick/2" do
    test "does nothing before events start tick" do
      assert {nil, nil, []} = WorldEvents.process_tick(500, 42)
    end

    test "does nothing on non-interval ticks" do
      assert {nil, nil, []} = WorldEvents.process_tick(1001, 42)
    end

    test "does nothing when cooldown has not elapsed" do
      WorldEvents.put_state(%{
        active_event: nil,
        event_start_tick: 0,
        last_event_tick: 900,
        event_history: []
      })

      # Tick 1000, last event at 900, cooldown is 500 — not enough time
      assert {nil, nil, []} = WorldEvents.process_tick(1000, 42)
    end

    test "ends active event after duration" do
      WorldEvents.put_state(%{
        active_event: :hiss_surge,
        event_start_tick: 1000,
        last_event_tick: 0,
        event_history: [{:hiss_surge, 1000}]
      })

      # event_duration is 150, so at tick 1200 (1000 + 200 > 150) it should end
      {started, ended, _effects} = WorldEvents.process_tick(1200, 42)
      assert started == nil
      assert ended == :hiss_surge

      state = WorldEvents.state()
      assert state.active_event == nil
    end

    test "applies ongoing effects for active event" do
      WorldEvents.put_state(%{
        active_event: :hiss_surge,
        event_start_tick: 1000,
        last_event_tick: 0,
        event_history: [{:hiss_surge, 1000}]
      })

      # Within duration, should apply effects
      {started, ended, _effects} = WorldEvents.process_tick(1100, 42)
      assert started == nil
      assert ended == nil
    end
  end

  describe "put_state/1" do
    test "stores state correctly" do
      state = %{
        active_event: :resonance_cascade,
        event_start_tick: 2000,
        last_event_tick: 1500,
        event_history: [{:resonance_cascade, 2000}]
      }

      WorldEvents.put_state(state)
      assert WorldEvents.state() == state
    end
  end

  describe "clear/0" do
    test "clears all event state" do
      WorldEvents.put_state(%{
        active_event: :hiss_surge,
        event_start_tick: 1000,
        last_event_tick: 500,
        event_history: [{:hiss_surge, 1000}]
      })

      WorldEvents.clear()
      # Re-init to get fresh state
      WorldEvents.init()
      state = WorldEvents.state()
      assert state.active_event == nil
      assert state.event_history == []
    end
  end
end
