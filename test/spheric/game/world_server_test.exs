defmodule Spheric.Game.WorldServerTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{WorldServer, WorldStore}

  # WorldServer is started by the application supervision tree,
  # so these tests run against the already-running instance.

  describe "tile access" do
    test "get_tile returns generated terrain data" do
      tile = WorldServer.get_tile({0, 8, 8})
      assert tile != nil
      assert tile.terrain in [:grassland, :desert, :tundra, :forest, :volcanic]
    end

    test "get_tile returns nil for out-of-range tile" do
      assert WorldServer.get_tile({99, 99, 99}) == nil
    end
  end

  describe "building placement" do
    test "place and retrieve a building" do
      key = {15, 7, 7}
      WorldStore.remove_building(key)

      assert :ok = WorldServer.place_building(key, :conveyor, 0)
      building = WorldServer.get_building(key)
      assert building.type == :conveyor
      assert building.orientation == 0

      WorldServer.remove_building(key)
    end

    test "cannot place building on occupied tile" do
      key = {16, 3, 3}
      WorldStore.remove_building(key)

      assert :ok = WorldServer.place_building(key, :conveyor, 0)
      assert {:error, :tile_occupied} = WorldServer.place_building(key, :conveyor, 1)

      WorldServer.remove_building(key)
    end

    test "cannot place building on invalid tile" do
      assert {:error, :invalid_tile} = WorldServer.place_building({99, 0, 0}, :miner, 0)
    end

    test "remove_building returns error when no building exists" do
      key = {17, 5, 5}
      WorldStore.remove_building(key)
      assert {:error, :no_building} = WorldServer.remove_building(key)
    end

    test "remove_building removes an existing building" do
      key = {18, 2, 2}
      WorldStore.remove_building(key)

      WorldServer.place_building(key, :smelter, 2)
      assert :ok = WorldServer.remove_building(key)
      assert WorldServer.get_building(key) == nil
    end

    test "cannot place invalid building type" do
      assert {:error, :invalid_building_type} = WorldServer.place_building({0, 0, 0}, :rocket, 0)
    end

    test "miner cannot be placed on tile without resources" do
      # Find a tile without resources
      tile = WorldStore.get_tile({0, 0, 0})

      if tile.resource == nil do
        WorldStore.remove_building({0, 0, 0})
        assert {:error, :invalid_placement} = WorldServer.place_building({0, 0, 0}, :miner, 0)
      end
    end

    test "conveyor can be placed on any valid tile" do
      key = {19, 4, 4}
      WorldStore.remove_building(key)

      assert :ok = WorldServer.place_building(key, :conveyor, 0)
      WorldServer.remove_building(key)
    end
  end

  describe "face snapshot" do
    test "returns tiles and buildings for a face" do
      snapshot = WorldServer.get_face_snapshot(0)
      assert is_list(snapshot.tiles)
      assert is_list(snapshot.buildings)
      assert length(snapshot.tiles) == 256
    end
  end

  describe "tick loop" do
    test "tick count advances" do
      count1 = WorldServer.tick_count()
      Process.sleep(250)
      count2 = WorldServer.tick_count()
      assert count2 > count1
    end
  end
end
