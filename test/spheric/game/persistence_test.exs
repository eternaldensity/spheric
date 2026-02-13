defmodule Spheric.Game.PersistenceTest do
  use Spheric.DataCase, async: false

  alias Spheric.Game.{Persistence, WorldStore}
  alias Spheric.Game.Schema.{World, Building, TileResource}

  # Use high face IDs to avoid collision with the running world (faces 0-29)
  @test_face 60

  setup do
    # Clean up any test worlds
    Repo.delete_all(World)

    # Ensure ETS tiles exist for our test face
    for row <- 0..3, col <- 0..3 do
      WorldStore.put_tiles([
        {{@test_face, row, col},
         %{
           terrain: :grassland,
           resource: if(row == 0 and col == 0, do: {:iron, 500}, else: nil)
         }}
      ])
    end

    # Clear dirty state from setup
    WorldStore.drain_dirty()

    on_exit(fn ->
      for row <- 0..3, col <- 0..3 do
        if WorldStore.has_building?({@test_face, row, col}) do
          WorldStore.remove_building({@test_face, row, col})
        end
      end

      WorldStore.drain_dirty()
    end)

    :ok
  end

  describe "ensure_world/3" do
    test "creates a new world record" do
      world = Persistence.ensure_world("test_world", 42, 16)
      assert world.id
      assert world.name == "test_world"
      assert world.seed == 42
      assert world.subdivisions == 16
    end

    test "returns existing world if name already exists" do
      w1 = Persistence.ensure_world("test_world", 42, 16)
      w2 = Persistence.ensure_world("test_world", 42, 16)
      assert w1.id == w2.id
    end
  end

  describe "save_dirty/4" do
    test "saves tile resources" do
      world = Persistence.ensure_world("test_save", 42, 16)

      # Simulate miner depleting a resource
      WorldStore.put_tile({@test_face, 0, 0}, %{terrain: :grassland, resource: {:iron, 450}})
      WorldStore.drain_dirty()

      Persistence.save_dirty(world.id, [{@test_face, 0, 0}], [], [])

      tr = Repo.get_by(TileResource, world_id: world.id, face_id: @test_face, row: 0, col: 0)
      assert tr.resource_type == "iron"
      assert tr.amount == 450
    end

    test "saves depleted resource as nil" do
      world = Persistence.ensure_world("test_save_nil", 42, 16)

      WorldStore.put_tile({@test_face, 0, 0}, %{terrain: :grassland, resource: nil})
      WorldStore.drain_dirty()

      Persistence.save_dirty(world.id, [{@test_face, 0, 0}], [], [])

      tr = Repo.get_by(TileResource, world_id: world.id, face_id: @test_face, row: 0, col: 0)
      assert tr.resource_type == nil
      assert tr.amount == nil
    end

    test "saves buildings" do
      world = Persistence.ensure_world("test_save_b", 42, 16)

      WorldStore.put_building({@test_face, 1, 1}, %{
        type: :conveyor,
        orientation: 2,
        state: %{item: nil}
      })

      WorldStore.drain_dirty()

      Persistence.save_dirty(world.id, [], [{@test_face, 1, 1}], [])

      b = Repo.get_by(Building, world_id: world.id, face_id: @test_face, row: 1, col: 1)
      assert b.type == "conveyor"
      assert b.orientation == 2
      assert b.state == %{"item" => nil}
    end

    test "saves building state with atom values serialized" do
      world = Persistence.ensure_world("test_save_state", 42, 16)

      WorldStore.put_building({@test_face, 2, 2}, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: :iron_ore, progress: 3, rate: 5}
      })

      WorldStore.drain_dirty()

      Persistence.save_dirty(world.id, [], [{@test_face, 2, 2}], [])

      b = Repo.get_by(Building, world_id: world.id, face_id: @test_face, row: 2, col: 2)
      assert b.state["output_buffer"] == "iron_ore"
      assert b.state["progress"] == 3
      assert b.state["rate"] == 5
    end

    test "deletes removed buildings" do
      world = Persistence.ensure_world("test_remove", 42, 16)

      # First save a building
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5}
      })

      WorldStore.drain_dirty()
      Persistence.save_dirty(world.id, [], [{@test_face, 3, 3}], [])
      assert Repo.get_by(Building, world_id: world.id, face_id: @test_face, row: 3, col: 3)

      # Then remove it
      WorldStore.remove_building({@test_face, 3, 3})
      WorldStore.drain_dirty()
      Persistence.save_dirty(world.id, [], [], [{@test_face, 3, 3}])

      refute Repo.get_by(Building, world_id: world.id, face_id: @test_face, row: 3, col: 3)
    end

    test "upsert updates existing records" do
      world = Persistence.ensure_world("test_upsert", 42, 16)

      WorldStore.put_tile({@test_face, 0, 0}, %{terrain: :grassland, resource: {:iron, 400}})
      WorldStore.drain_dirty()
      Persistence.save_dirty(world.id, [{@test_face, 0, 0}], [], [])

      WorldStore.put_tile({@test_face, 0, 0}, %{terrain: :grassland, resource: {:iron, 350}})
      WorldStore.drain_dirty()
      Persistence.save_dirty(world.id, [{@test_face, 0, 0}], [], [])

      tr = Repo.get_by(TileResource, world_id: world.id, face_id: @test_face, row: 0, col: 0)
      assert tr.amount == 350
    end
  end

  describe "load_world/1" do
    test "returns :none when no world exists" do
      assert :none = Persistence.load_world("nonexistent")
    end

    test "loads saved buildings into ETS" do
      world = Persistence.ensure_world("test_load", 42, 16)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%Building{
        world_id: world.id,
        face_id: 5,
        row: 3,
        col: 4,
        type: "conveyor",
        orientation: 1,
        state: %{"item" => nil},
        inserted_at: now,
        updated_at: now
      })

      assert {:ok, loaded} = Persistence.load_world("test_load")
      assert loaded.seed == 42

      building = WorldStore.get_building({5, 3, 4})
      assert building.type == :conveyor
      assert building.orientation == 1
      assert building.state.item == nil

      # Cleanup
      WorldStore.remove_building({5, 3, 4})
      WorldStore.drain_dirty()
    end

    test "loads saved tile resources and overlays onto generated terrain" do
      world = Persistence.ensure_world("test_load_tiles", 42, 16)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Save a modified resource for a specific tile
      Repo.insert!(%TileResource{
        world_id: world.id,
        face_id: 0,
        row: 0,
        col: 0,
        resource_type: "iron",
        amount: 123,
        inserted_at: now,
        updated_at: now
      })

      assert {:ok, _loaded} = Persistence.load_world("test_load_tiles")

      tile = WorldStore.get_tile({0, 0, 0})
      assert tile.resource == {:iron, 123}
    end

    test "loads depleted resources as nil" do
      world = Persistence.ensure_world("test_load_depleted", 42, 16)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%TileResource{
        world_id: world.id,
        face_id: 0,
        row: 1,
        col: 1,
        resource_type: nil,
        amount: nil,
        inserted_at: now,
        updated_at: now
      })

      assert {:ok, _loaded} = Persistence.load_world("test_load_depleted")

      tile = WorldStore.get_tile({0, 1, 1})
      assert tile.resource == nil
    end

    test "loads building with atom state values" do
      world = Persistence.ensure_world("test_load_atoms", 42, 16)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%Building{
        world_id: world.id,
        face_id: 5,
        row: 5,
        col: 5,
        type: "miner",
        orientation: 2,
        state: %{"output_buffer" => "iron_ore", "progress" => 4, "rate" => 5},
        inserted_at: now,
        updated_at: now
      })

      assert {:ok, _loaded} = Persistence.load_world("test_load_atoms")

      building = WorldStore.get_building({5, 5, 5})
      assert building.type == :miner
      assert building.state.output_buffer == :iron_ore
      assert building.state.progress == 4
      assert building.state.rate == 5

      # Cleanup
      WorldStore.remove_building({5, 5, 5})
      WorldStore.drain_dirty()
    end
  end
end
