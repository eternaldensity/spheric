defmodule Spheric.Game.Behaviors.ConveyorTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.Conveyor

  test "initial_state has empty item slot" do
    state = Conveyor.initial_state()
    assert state.item == nil
  end
end
