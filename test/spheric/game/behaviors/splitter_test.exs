defmodule Spheric.Game.Behaviors.SplitterTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.Splitter

  describe "initial_state/0" do
    test "starts with no item" do
      state = Splitter.initial_state()
      assert state.item == nil
    end

    test "starts with :left as next output" do
      state = Splitter.initial_state()
      assert state.next_output == :left
    end
  end

  describe "output_directions/1" do
    test "orientation 0 outputs left=3, right=1" do
      {left, right} = Splitter.output_directions(0)
      assert left == 3
      assert right == 1
    end

    test "orientation 1 outputs left=0, right=2" do
      {left, right} = Splitter.output_directions(1)
      assert left == 0
      assert right == 2
    end

    test "orientation 2 outputs left=1, right=3" do
      {left, right} = Splitter.output_directions(2)
      assert left == 1
      assert right == 3
    end

    test "orientation 3 outputs left=2, right=0" do
      {left, right} = Splitter.output_directions(3)
      assert left == 2
      assert right == 0
    end
  end
end
