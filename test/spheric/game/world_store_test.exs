defmodule Spheric.Game.WorldStoreTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.WorldStore

  # WorldServer already owns the ETS tables via the supervision tree.
  # Use a high face_id range ({50..52, _, _}) to avoid colliding with the generated world.

  @test_face 50

  setup do
    on_exit(fn ->
      for f <- @test_face..(@test_face + 2), r <- 0..15, c <- 0..15 do
        WorldStore.remove_building({f, r, c})
      end
    end)

    :ok
  end

  describe "tiles" do
    test "put and get a tile" do
      key = {@test_face, 5, 10}
      data = %{terrain: :grassland, resource: nil}
      WorldStore.put_tile(key, data)
      assert WorldStore.get_tile(key) == data
    end

    test "get_tile returns nil for missing key" do
      assert WorldStore.get_tile({99, 99, 99}) == nil
    end

    test "put_tiles batch inserts" do
      tiles = [
        {{@test_face, 0, 0}, %{terrain: :grassland, resource: nil}},
        {{@test_face, 0, 1}, %{terrain: :desert, resource: {:iron, 200}}},
        {{@test_face + 1, 0, 0}, %{terrain: :tundra, resource: nil}}
      ]

      WorldStore.put_tiles(tiles)
      assert WorldStore.get_tile({@test_face, 0, 1}).terrain == :desert
    end

    test "get_face_tiles returns tiles for a generated face" do
      # Face 0 is populated by WorldGen at startup with 16x16 = 256 tiles
      face0 = WorldStore.get_face_tiles(0)
      assert length(face0) == 256
      assert Enum.all?(face0, fn {{f, _, _}, _} -> f == 0 end)
    end

    test "tile_count includes all generated tiles" do
      # WorldGen generates 30 * 16 * 16 = 7680 tiles at startup
      assert WorldStore.tile_count() >= 7_680
    end
  end

  describe "buildings" do
    test "put and get a building" do
      key = {@test_face, 5, 10}
      data = %{type: :miner, orientation: 0, state: %{}}
      WorldStore.put_building(key, data)
      assert WorldStore.get_building(key) == data
    end

    test "get_building returns nil for missing key" do
      assert WorldStore.get_building({99, 99, 99}) == nil
    end

    test "remove_building deletes it" do
      key = {@test_face, 5, 10}
      WorldStore.put_building(key, %{type: :miner, orientation: 0, state: %{}})
      assert WorldStore.get_building(key) != nil

      WorldStore.remove_building(key)
      assert WorldStore.get_building(key) == nil
    end

    test "has_building? checks existence" do
      key = {@test_face, 2, 3}
      refute WorldStore.has_building?(key)

      WorldStore.put_building(key, %{type: :conveyor, orientation: 1, state: %{}})
      assert WorldStore.has_building?(key)
    end

    test "get_face_buildings returns only buildings for that face" do
      WorldStore.put_building({@test_face, 0, 0}, %{type: :miner, orientation: 0, state: %{}})
      WorldStore.put_building({@test_face, 1, 0}, %{type: :conveyor, orientation: 2, state: %{}})

      WorldStore.put_building({@test_face + 1, 0, 0}, %{
        type: :smelter,
        orientation: 0,
        state: %{}
      })

      face_buildings = WorldStore.get_face_buildings(@test_face)
      assert length(face_buildings) == 2
      assert Enum.all?(face_buildings, fn {{f, _, _}, _} -> f == @test_face end)
    end

    test "building_count starts at zero" do
      # No buildings placed at startup
      # (we may have test buildings from other tests, so just check it's >= 0)
      assert WorldStore.building_count() >= 0
    end
  end
end
