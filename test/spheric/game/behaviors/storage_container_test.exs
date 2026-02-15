defmodule Spheric.Game.Behaviors.StorageContainerTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.StorageContainer

  describe "initial_state/0" do
    test "starts empty" do
      state = StorageContainer.initial_state()
      assert state.item_type == nil
      assert state.count == 0
      assert state.capacity == 100
    end
  end

  describe "capacity/0" do
    test "returns 100" do
      assert StorageContainer.capacity() == 100
    end
  end

  describe "try_accept_item/2" do
    test "accepts first item into empty container" do
      state = StorageContainer.initial_state()
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.item_type == :iron_ingot
      assert result.count == 1
    end

    test "accepts same item type" do
      state = %{item_type: :iron_ingot, count: 5, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.count == 6
    end

    test "rejects different item type" do
      state = %{item_type: :iron_ingot, count: 5, capacity: 100}
      result = StorageContainer.try_accept_item(state, :copper_ingot)
      assert result == nil
    end

    test "rejects when at capacity" do
      state = %{item_type: :iron_ingot, count: 100, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result == nil
    end

    test "fills up to capacity" do
      state = %{item_type: :iron_ingot, count: 99, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.count == 100
    end
  end
end
