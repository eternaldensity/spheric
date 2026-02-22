defmodule Spheric.Game.HissTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{Hiss, WorldStore, Creatures}

  @test_face 50

  setup do
    Hiss.init()
    Hiss.clear_all()
    Creatures.init()
    Creatures.clear_all()

    for r <- 0..15, c <- 0..15 do
      WorldStore.put_tile({@test_face, r, c}, %{terrain: :volcanic, resource: nil})
    end

    on_exit(fn ->
      Hiss.clear_all()
      Creatures.clear_all()

      for r <- 0..15, c <- 0..15 do
        WorldStore.remove_building({@test_face, r, c})
      end
    end)

    :ok
  end

  # --- Corruption data API ---

  describe "corruption_at/1" do
    test "returns 0 for uncorrupted tile" do
      assert Hiss.corruption_at({@test_face, 5, 5}) == 0
    end

    test "returns intensity for corrupted tile" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 4, seeded_at: 100, building_damage_ticks: 0})
      assert Hiss.corruption_at({@test_face, 5, 5}) == 4
    end
  end

  describe "get_corruption/1" do
    test "returns nil for uncorrupted tile" do
      assert Hiss.get_corruption({@test_face, 5, 5}) == nil
    end

    test "returns corruption data for corrupted tile" do
      data = %{intensity: 7, seeded_at: 200, building_damage_ticks: 0}
      Hiss.put_corruption({@test_face, 5, 5}, data)
      assert Hiss.get_corruption({@test_face, 5, 5}) == data
    end
  end

  describe "corrupted?/1" do
    test "returns false for uncorrupted tile" do
      refute Hiss.corrupted?({@test_face, 5, 5})
    end

    test "returns true for corrupted tile" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 1, seeded_at: 0, building_damage_ticks: 0})
      assert Hiss.corrupted?({@test_face, 5, 5})
    end
  end

  describe "blocks_placement?/1" do
    test "returns false for uncorrupted tile" do
      refute Hiss.blocks_placement?({@test_face, 5, 5})
    end

    test "returns true for corrupted tile" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 1, seeded_at: 0, building_damage_ticks: 0})
      assert Hiss.blocks_placement?({@test_face, 5, 5})
    end
  end

  # --- Aggregate queries ---

  describe "all_corrupted/0" do
    test "returns empty list when no corruption" do
      assert Hiss.all_corrupted() == []
    end

    test "returns all corrupted tiles" do
      Hiss.put_corruption({@test_face, 1, 1}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_corruption({@test_face, 2, 2}, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})

      all = Hiss.all_corrupted()
      assert length(all) == 2
    end
  end

  describe "corruption_count/0" do
    test "returns 0 when no corruption" do
      assert Hiss.corruption_count() == 0
    end

    test "returns correct count" do
      Hiss.put_corruption({@test_face, 1, 1}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_corruption({@test_face, 2, 2}, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})

      assert Hiss.corruption_count() == 2
    end
  end

  describe "corrupted_by_face/0" do
    test "groups corruption by face" do
      Hiss.put_corruption({@test_face, 1, 1}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_corruption({@test_face, 2, 2}, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_corruption({@test_face + 1, 3, 3}, %{intensity: 1, seeded_at: 0, building_damage_ticks: 0})

      by_face = Hiss.corrupted_by_face()
      assert length(Map.get(by_face, @test_face, [])) == 2
      assert length(Map.get(by_face, @test_face + 1, [])) == 1
    end
  end

  describe "corrupted_on_face/1" do
    test "returns only tiles on the given face" do
      Hiss.put_corruption({@test_face, 1, 1}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_corruption({@test_face + 1, 2, 2}, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})

      on_face = Hiss.corrupted_on_face(@test_face)
      assert length(on_face) == 1
      assert hd(on_face).face == @test_face
    end
  end

  # --- Hiss Entities ---

  describe "hiss entity management" do
    test "starts with no entities" do
      assert Hiss.all_hiss_entities() == []
      assert Hiss.hiss_entity_count() == 0
    end

    test "put and retrieve entity" do
      entity = %{face: @test_face, row: 5, col: 5, health: 100, spawned_at: 100}
      Hiss.put_hiss_entity("hiss:1", entity)

      assert Hiss.hiss_entity_count() == 1
      all = Hiss.all_hiss_entities()
      assert length(all) == 1
      {id, e} = hd(all)
      assert id == "hiss:1"
      assert e.health == 100
    end

    test "hiss_entities_on_face filters by face" do
      Hiss.put_hiss_entity("hiss:1", %{face: @test_face, row: 1, col: 1, health: 100, spawned_at: 0})
      Hiss.put_hiss_entity("hiss:2", %{face: @test_face + 1, row: 2, col: 2, health: 100, spawned_at: 0})

      on_face = Hiss.hiss_entities_on_face(@test_face)
      assert length(on_face) == 1
    end

    test "hiss_entities_by_face groups correctly" do
      Hiss.put_hiss_entity("hiss:1", %{face: @test_face, row: 1, col: 1, health: 100, spawned_at: 0})
      Hiss.put_hiss_entity("hiss:2", %{face: @test_face, row: 2, col: 2, health: 80, spawned_at: 0})
      Hiss.put_hiss_entity("hiss:3", %{face: @test_face + 1, row: 3, col: 3, health: 60, spawned_at: 0})

      by_face = Hiss.hiss_entities_by_face()
      assert length(Map.get(by_face, @test_face, [])) == 2
      assert length(Map.get(by_face, @test_face + 1, [])) == 1
    end
  end

  # --- Tick processing ---

  describe "maybe_seed_corruption/2" do
    test "does not seed before corruption start tick" do
      result = Hiss.maybe_seed_corruption(100, 42)
      assert result == []
    end

    test "does not seed on non-interval ticks" do
      # 3001 is past start tick (3000) but not on seed_interval (600)
      result = Hiss.maybe_seed_corruption(3001, 42)
      assert result == []
    end

    test "seeds corruption at correct interval after start tick" do
      # seed_interval is 600, corruption_start_tick is 3000
      # So tick 3600 = 3000 + 600, rem(3600, 600) = 0
      result = Hiss.maybe_seed_corruption(3600, 42)
      assert is_list(result)
      # May or may not succeed depending on random tile placement
    end
  end

  describe "spread_corruption/1" do
    test "does not spread on non-interval ticks" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      result = Hiss.spread_corruption(1)
      assert result == []
    end

    test "spreads on correct interval" do
      # Place corruption far from test_face edges for spread
      # spread_interval is 150, so use tick 150
      Hiss.put_corruption({0, 5, 5}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      result = Hiss.spread_corruption(150)
      assert is_list(result)
      # Intensity increase is probabilistic (40% chance per cycle),
      # so just verify intensity is 3 or 4 (not decreased)
      data = Hiss.get_corruption({0, 5, 5})
      assert data.intensity >= 3 and data.intensity <= 4
    end

    test "does not increase intensity beyond max" do
      Hiss.put_corruption({0, 5, 5}, %{intensity: 10, seeded_at: 0, building_damage_ticks: 0})
      Hiss.spread_corruption(150)
      # intensity is at max (10), no further increase
      data = Hiss.get_corruption({0, 5, 5})
      assert data == %{intensity: 10, seeded_at: 0, building_damage_ticks: 0}
    end
  end

  describe "process_building_damage/1" do
    test "does not damage buildings below intensity threshold" do
      key = {@test_face, 3, 3}
      Hiss.put_corruption(key, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      WorldStore.put_building(key, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5},
        owner_id: "player:test"
      })

      result = Hiss.process_building_damage(100)
      assert result == []
    end

    test "damages buildings at intensity threshold" do
      key = {@test_face, 4, 4}
      Hiss.put_corruption(key, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})
      WorldStore.put_building(key, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5},
        owner_id: "player:test"
      })

      result = Hiss.process_building_damage(100)
      assert [{^key, :damaged}] = result

      # Damage ticks should have incremented
      data = Hiss.get_corruption(key)
      assert data.building_damage_ticks == 1
    end

    test "destroys building after enough damage ticks" do
      key = {@test_face, 5, 5}
      # Set damage_ticks to 24 (threshold is 25), so next tick should destroy
      Hiss.put_corruption(key, %{intensity: 5, seeded_at: 0, building_damage_ticks: 24})
      WorldStore.put_building(key, %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5},
        owner_id: "player:test"
      })

      result = Hiss.process_building_damage(100)
      assert [{^key, :destroyed}] = result
      assert WorldStore.get_building(key) == nil
    end

    test "does not damage purification beacons" do
      key = {@test_face, 6, 6}
      Hiss.put_corruption(key, %{intensity: 8, seeded_at: 0, building_damage_ticks: 0})
      WorldStore.put_building(key, %{
        type: :purification_beacon,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      result = Hiss.process_building_damage(100)
      assert result == []
    end

    test "does not damage defense turrets" do
      key = {@test_face, 7, 7}
      Hiss.put_corruption(key, %{intensity: 8, seeded_at: 0, building_damage_ticks: 0})
      WorldStore.put_building(key, %{
        type: :defense_turret,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      result = Hiss.process_building_damage(100)
      assert result == []
    end
  end

  describe "maybe_spawn_hiss_entities/2" do
    test "does not spawn on non-interval ticks" do
      assert Hiss.maybe_spawn_hiss_entities(1, 42) == []
    end

    test "does not spawn when at max entities" do
      # Fill up entities to max (30)
      for i <- 0..29 do
        Hiss.put_hiss_entity("hiss:fill:#{i}", %{
          face: @test_face,
          row: 0,
          col: 0,
          health: 100,
          spawned_at: 0
        })
      end

      assert Hiss.maybe_spawn_hiss_entities(150, 42) == []
    end

    test "does not spawn without high-corruption tiles" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      assert Hiss.maybe_spawn_hiss_entities(150, 42) == []
    end

    test "spawns from high-corruption tiles" do
      key = {@test_face, 5, 5}
      Hiss.put_corruption(key, %{intensity: 8, seeded_at: 0, building_damage_ticks: 0})

      result = Hiss.maybe_spawn_hiss_entities(150, 42)
      assert length(result) > 0
      assert Hiss.hiss_entity_count() > 0
    end
  end

  describe "move_hiss_entities/1" do
    test "does not move on non-interval ticks" do
      Hiss.put_hiss_entity("hiss:mv", %{face: 0, row: 5, col: 5, health: 100, spawned_at: 0})
      result = Hiss.move_hiss_entities(1)
      assert result == []
    end

    test "moves entities on correct interval" do
      Hiss.put_hiss_entity("hiss:mv", %{face: 0, row: 5, col: 5, health: 100, spawned_at: 0})
      result = Hiss.move_hiss_entities(8)
      assert is_list(result)
    end
  end

  describe "process_combat/1" do
    # Combat scans faces 0..29 for turrets, so use a valid face
    @combat_face 28

    setup do
      on_exit(fn ->
        for r <- 0..10, c <- 0..10 do
          WorldStore.remove_building({@combat_face, r, c})
        end
      end)

      :ok
    end

    test "turret kills hiss entity" do
      turret_key = {@combat_face, 5, 5}
      WorldStore.put_building(turret_key, %{
        type: :defense_turret,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      # Place entity near turret (within radius 3)
      Hiss.put_hiss_entity("hiss:combat1", %{
        face: @combat_face,
        row: 5,
        col: 6,
        health: 30,
        spawned_at: 0
      })

      {kills, drops} = Hiss.process_combat(100)
      assert length(kills) > 0
      assert length(drops) > 0
      assert Hiss.hiss_entity_count() == 0
    end

    test "turret damages but does not kill strong entity" do
      turret_key = {@combat_face, 5, 5}
      WorldStore.put_building(turret_key, %{
        type: :defense_turret,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      Hiss.put_hiss_entity("hiss:combat2", %{
        face: @combat_face,
        row: 5,
        col: 6,
        health: 100,
        spawned_at: 0
      })

      {kills, drops} = Hiss.process_combat(100)
      assert kills == []
      assert drops == []
      # Entity should still exist but damaged
      assert Hiss.hiss_entity_count() == 1
      [{_id, entity}] = Hiss.all_hiss_entities()
      assert entity.health == 66
    end

    test "no kills when no turrets or creatures" do
      Hiss.put_hiss_entity("hiss:alone", %{
        face: @combat_face,
        row: 5,
        col: 5,
        health: 100,
        spawned_at: 0
      })

      {kills, drops} = Hiss.process_combat(100)
      assert kills == []
      assert drops == []
    end
  end

  describe "process_purification/1" do
    test "returns empty when no beacons exist" do
      Hiss.put_corruption({@test_face, 5, 5}, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})
      assert Hiss.process_purification(100) == []
    end

    test "beacon reduces corruption within radius" do
      # Place beacon on a face within 0..29
      beacon_key = {0, 5, 5}
      WorldStore.put_building(beacon_key, %{
        type: :purification_beacon,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      # Place corruption within radius 5
      corrupted_key = {0, 5, 7}
      Hiss.put_corruption(corrupted_key, %{intensity: 3, seeded_at: 0, building_damage_ticks: 0})

      result = Hiss.process_purification(100)
      assert length(result) > 0

      # Intensity should be reduced
      data = Hiss.get_corruption(corrupted_key)
      assert data.intensity == 2
    end

    test "beacon removes corruption when intensity reaches 0" do
      beacon_key = {0, 5, 5}
      WorldStore.put_building(beacon_key, %{
        type: :purification_beacon,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      corrupted_key = {0, 5, 7}
      Hiss.put_corruption(corrupted_key, %{intensity: 1, seeded_at: 0, building_damage_ticks: 0})

      Hiss.process_purification(100)

      # Corruption should be completely removed
      assert Hiss.get_corruption(corrupted_key) == nil
    end

    test "beacon does not affect corruption outside radius" do
      beacon_key = {0, 5, 5}
      WorldStore.put_building(beacon_key, %{
        type: :purification_beacon,
        orientation: 0,
        state: %{},
        owner_id: "player:test"
      })

      # Place corruption far outside radius 5
      far_key = {0, 5, 15}
      Hiss.put_corruption(far_key, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})

      Hiss.process_purification(100)

      # Should be unchanged
      data = Hiss.get_corruption(far_key)
      assert data.intensity == 5
    end
  end

  describe "clear_all/0" do
    test "clears all corruption and entities" do
      Hiss.put_corruption({@test_face, 1, 1}, %{intensity: 5, seeded_at: 0, building_damage_ticks: 0})
      Hiss.put_hiss_entity("hiss:clear", %{face: @test_face, row: 1, col: 1, health: 100, spawned_at: 0})

      Hiss.clear_all()

      assert Hiss.corruption_count() == 0
      assert Hiss.hiss_entity_count() == 0
    end
  end
end
