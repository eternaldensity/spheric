defmodule Spheric.Game.Behaviors.ConveyorTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.{Conveyor, ConveyorMk2, ConveyorMk3}

  test "Mk1 initial_state has empty item slot and zero move_ticks" do
    state = Conveyor.initial_state()
    assert state.item == nil
    assert state.move_ticks == 0
  end

  test "Mk2 initial_state has empty slots and zero move_ticks" do
    state = ConveyorMk2.initial_state()
    assert state.item == nil
    assert state.buffer == nil
    assert state.move_ticks == 0
  end

  test "Mk3 initial_state has empty slots" do
    state = ConveyorMk3.initial_state()
    assert state.item == nil
    assert state.buffer1 == nil
    assert state.buffer2 == nil
  end
end
