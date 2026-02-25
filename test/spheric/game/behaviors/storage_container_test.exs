defmodule Spheric.Game.Behaviors.StorageContainerTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Behaviors.StorageContainer

  describe "initial_state/0" do
    test "starts empty with zero inserted_count" do
      state = StorageContainer.initial_state()
      assert state.item_type == nil
      assert state.count == 0
      assert state.inserted_count == 0
      assert state.capacity == 100
    end
  end

  describe "capacity/0" do
    test "returns 100" do
      assert StorageContainer.capacity() == 100
    end
  end

  describe "total_count/1" do
    test "sums count and inserted_count" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 3, capacity: 100}
      assert StorageContainer.total_count(state) == 8
    end

    test "handles missing inserted_count for backward compat" do
      state = %{item_type: :iron_ingot, count: 5, capacity: 100}
      assert StorageContainer.total_count(state) == 5
    end
  end

  describe "try_accept_item/2 (arm insertion -> inserted_count)" do
    test "accepts first item into empty container" do
      state = StorageContainer.initial_state()
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.item_type == :iron_ingot
      assert result.count == 0
      assert result.inserted_count == 1
    end

    test "increments inserted_count, not count" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 2, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.count == 5
      assert result.inserted_count == 3
    end

    test "rejects different item type" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 0, capacity: 100}
      result = StorageContainer.try_accept_item(state, :copper_ingot)
      assert result == nil
    end

    test "rejects when total count at capacity" do
      state = %{item_type: :iron_ingot, count: 90, inserted_count: 10, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result == nil
    end

    test "accepts when count alone is at capacity but total is not" do
      # This shouldn't happen in practice, but verifying total check
      state = %{item_type: :iron_ingot, count: 99, inserted_count: 0, capacity: 100}
      result = StorageContainer.try_accept_item(state, :iron_ingot)
      assert result.inserted_count == 1
    end
  end

  describe "try_accept_stored/2 (conveyor push -> count)" do
    test "accepts first item into empty container" do
      state = StorageContainer.initial_state()
      result = StorageContainer.try_accept_stored(state, :iron_ingot)
      assert result.item_type == :iron_ingot
      assert result.count == 1
      assert result.inserted_count == 0
    end

    test "increments count, not inserted_count" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 2, capacity: 100}
      result = StorageContainer.try_accept_stored(state, :iron_ingot)
      assert result.count == 6
      assert result.inserted_count == 2
    end

    test "rejects when total at capacity" do
      state = %{item_type: :iron_ingot, count: 90, inserted_count: 10, capacity: 100}
      result = StorageContainer.try_accept_stored(state, :iron_ingot)
      assert result == nil
    end

    test "rejects different item type" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 0, capacity: 100}
      result = StorageContainer.try_accept_stored(state, :copper_ingot)
      assert result == nil
    end
  end

  describe "consolidate/1" do
    test "merges inserted_count into count" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 3, capacity: 100}
      result = StorageContainer.consolidate(state)
      assert result.count == 8
      assert result.inserted_count == 0
    end

    test "no-op when inserted_count is 0" do
      state = %{item_type: :iron_ingot, count: 5, inserted_count: 0, capacity: 100}
      result = StorageContainer.consolidate(state)
      assert result.count == 5
      assert result.inserted_count == 0
    end

    test "handles missing inserted_count for backward compat" do
      state = %{item_type: :iron_ingot, count: 5, capacity: 100}
      result = StorageContainer.consolidate(state)
      assert result.count == 5
    end
  end
end
