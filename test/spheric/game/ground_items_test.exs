defmodule Spheric.Game.GroundItemsTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.GroundItems

  @test_face 53

  setup do
    GroundItems.init()
    GroundItems.clear()

    on_exit(fn ->
      GroundItems.clear()
    end)

    :ok
  end

  describe "get/1" do
    test "returns empty map for empty tile" do
      assert GroundItems.get({@test_face, 5, 5}) == %{}
    end

    test "returns items on tile" do
      GroundItems.add({@test_face, 5, 5}, :iron_ingot, 3)
      assert GroundItems.get({@test_face, 5, 5}) == %{iron_ingot: 3}
    end
  end

  describe "add/3" do
    test "adds items to empty tile" do
      GroundItems.add({@test_face, 1, 1}, :iron_ingot, 5)
      assert GroundItems.get({@test_face, 1, 1}) == %{iron_ingot: 5}
    end

    test "defaults count to 1" do
      GroundItems.add({@test_face, 1, 1}, :copper_ingot)
      assert GroundItems.get({@test_face, 1, 1}) == %{copper_ingot: 1}
    end

    test "stacks same item type" do
      GroundItems.add({@test_face, 2, 2}, :iron_ingot, 3)
      GroundItems.add({@test_face, 2, 2}, :iron_ingot, 2)
      assert GroundItems.get({@test_face, 2, 2}) == %{iron_ingot: 5}
    end

    test "supports multiple item types on same tile" do
      GroundItems.add({@test_face, 3, 3}, :iron_ingot, 2)
      GroundItems.add({@test_face, 3, 3}, :copper_ingot, 1)
      items = GroundItems.get({@test_face, 3, 3})
      assert items.iron_ingot == 2
      assert items.copper_ingot == 1
    end
  end

  describe "take/2" do
    test "takes one item from tile" do
      GroundItems.add({@test_face, 4, 4}, :iron_ingot, 3)
      assert :ok == GroundItems.take({@test_face, 4, 4}, :iron_ingot)
      assert GroundItems.get({@test_face, 4, 4}) == %{iron_ingot: 2}
    end

    test "returns :empty when item not present" do
      assert :empty == GroundItems.take({@test_face, 5, 5}, :iron_ingot)
    end

    test "removes item type when count reaches 0" do
      GroundItems.add({@test_face, 6, 6}, :iron_ingot, 1)
      assert :ok == GroundItems.take({@test_face, 6, 6}, :iron_ingot)
      assert GroundItems.get({@test_face, 6, 6}) == %{}
    end

    test "cleans up tile entry when all items removed" do
      GroundItems.add({@test_face, 7, 7}, :iron_ingot, 1)
      GroundItems.take({@test_face, 7, 7}, :iron_ingot)
      # Should be empty now and cleaned up
      assert GroundItems.get({@test_face, 7, 7}) == %{}
    end

    test "leaves other items when one type is depleted" do
      GroundItems.add({@test_face, 8, 8}, :iron_ingot, 1)
      GroundItems.add({@test_face, 8, 8}, :copper_ingot, 2)

      GroundItems.take({@test_face, 8, 8}, :iron_ingot)
      items = GroundItems.get({@test_face, 8, 8})
      refute Map.has_key?(items, :iron_ingot)
      assert items.copper_ingot == 2
    end
  end

  describe "items_near/2" do
    test "returns items within radius" do
      GroundItems.add({@test_face, 5, 5}, :iron_ingot, 1)
      GroundItems.add({@test_face, 6, 6}, :copper_ingot, 2)
      GroundItems.add({@test_face, 15, 15}, :wire, 1)

      nearby = GroundItems.items_near({@test_face, 5, 5}, 3)
      assert length(nearby) == 2
    end

    test "excludes items outside radius" do
      GroundItems.add({@test_face, 5, 5}, :iron_ingot, 1)
      GroundItems.add({@test_face, 15, 15}, :wire, 1)

      nearby = GroundItems.items_near({@test_face, 5, 5}, 2)
      assert length(nearby) == 1
    end

    test "only returns items on same face" do
      GroundItems.add({@test_face, 5, 5}, :iron_ingot, 1)
      GroundItems.add({@test_face + 1, 5, 5}, :copper_ingot, 1)

      nearby = GroundItems.items_near({@test_face, 5, 5}, 10)
      assert length(nearby) == 1
    end
  end

  describe "all_on_face/1" do
    test "returns items on specified face" do
      GroundItems.add({@test_face, 1, 1}, :iron_ingot, 1)
      GroundItems.add({@test_face, 2, 2}, :copper_ingot, 1)
      GroundItems.add({@test_face + 1, 3, 3}, :wire, 1)

      on_face = GroundItems.all_on_face(@test_face)
      assert length(on_face) == 2
    end
  end

  describe "all/0" do
    test "returns empty list initially" do
      assert GroundItems.all() == []
    end

    test "returns all ground items" do
      GroundItems.add({@test_face, 1, 1}, :iron_ingot, 1)
      GroundItems.add({@test_face + 1, 2, 2}, :copper_ingot, 1)

      assert length(GroundItems.all()) == 2
    end
  end

  describe "items_by_face/0" do
    test "groups items by face" do
      GroundItems.add({@test_face, 1, 1}, :iron_ingot, 1)
      GroundItems.add({@test_face, 2, 2}, :copper_ingot, 2)
      GroundItems.add({@test_face + 1, 3, 3}, :wire, 1)

      by_face = GroundItems.items_by_face()
      assert length(Map.get(by_face, @test_face, [])) == 2
      assert length(Map.get(by_face, @test_face + 1, [])) == 1
    end
  end

  describe "put_all/1" do
    test "bulk inserts entries" do
      entries = [
        {{@test_face, 1, 1}, %{iron_ingot: 5}},
        {{@test_face, 2, 2}, %{copper_ingot: 3}}
      ]

      GroundItems.put_all(entries)

      assert GroundItems.get({@test_face, 1, 1}) == %{iron_ingot: 5}
      assert GroundItems.get({@test_face, 2, 2}) == %{copper_ingot: 3}
    end
  end

  describe "clear/0" do
    test "removes all items" do
      GroundItems.add({@test_face, 1, 1}, :iron_ingot, 5)
      GroundItems.add({@test_face, 2, 2}, :copper_ingot, 3)

      GroundItems.clear()
      assert GroundItems.all() == []
    end
  end
end
