defmodule Spheric.Game.CreaturesTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{Creatures, WorldStore}

  # Use high face IDs to avoid collisions with generated world
  @test_face 55

  setup do
    Creatures.init()
    Creatures.clear_all()

    # Ensure test tiles exist
    for r <- 0..10, c <- 0..10 do
      WorldStore.put_tile({@test_face, r, c}, %{terrain: :volcanic, resource: nil})
    end

    on_exit(fn ->
      Creatures.clear_all()

      for r <- 0..10, c <- 0..10 do
        WorldStore.remove_building({@test_face, r, c})
      end
    end)

    :ok
  end

  describe "creature_types/0" do
    test "returns all 8 creature types" do
      types = Creatures.creature_types()
      assert map_size(types) == 8

      assert Map.has_key?(types, :ember_wisp)
      assert Map.has_key?(types, :frost_shard)
      assert Map.has_key?(types, :quartz_drone)
      assert Map.has_key?(types, :shadow_tendril)
      assert Map.has_key?(types, :copper_beetle)
      assert Map.has_key?(types, :spore_cloud)
      assert Map.has_key?(types, :static_mote)
      assert Map.has_key?(types, :void_fragment)
    end
  end

  describe "display_name/1" do
    test "returns human-readable names" do
      assert Creatures.display_name(:ember_wisp) == "Ember Wisp"
      assert Creatures.display_name(:frost_shard) == "Frost Shard"
      assert Creatures.display_name(:void_fragment) == "Void Fragment"
    end
  end

  describe "boost_info/1" do
    test "returns boost info for known types" do
      boost = Creatures.boost_info(:ember_wisp)
      assert boost.type == :speed
      assert boost.amount == 0.40

      boost = Creatures.boost_info(:void_fragment)
      assert boost.type == :all
      assert boost.amount == 0.15
    end

    test "returns nil for unknown types" do
      assert Creatures.boost_info(:nonexistent) == nil
    end
  end

  describe "wild creature management" do
    test "put and get wild creature" do
      creature = %{type: :ember_wisp, face: @test_face, row: 5, col: 5, spawned_at: 100}
      Creatures.put_wild_creature("test:1", creature)

      assert Creatures.get_wild_creature("test:1") == creature
      assert Creatures.wild_creature_count() == 1
    end

    test "all_wild_creatures returns all creatures" do
      Creatures.put_wild_creature("test:1", %{
        type: :ember_wisp,
        face: @test_face,
        row: 1,
        col: 1,
        spawned_at: 0
      })

      Creatures.put_wild_creature("test:2", %{
        type: :frost_shard,
        face: @test_face,
        row: 2,
        col: 2,
        spawned_at: 0
      })

      all = Creatures.all_wild_creatures()
      assert length(all) == 2
    end

    test "wild_creatures_on_face filters by face" do
      Creatures.put_wild_creature("test:1", %{
        type: :ember_wisp,
        face: @test_face,
        row: 1,
        col: 1,
        spawned_at: 0
      })

      Creatures.put_wild_creature("test:2", %{
        type: :frost_shard,
        face: @test_face + 1,
        row: 2,
        col: 2,
        spawned_at: 0
      })

      on_face = Creatures.wild_creatures_on_face(@test_face)
      assert length(on_face) == 1
    end

    test "creatures_by_face groups correctly" do
      Creatures.put_wild_creature("test:1", %{
        type: :ember_wisp,
        face: @test_face,
        row: 1,
        col: 1,
        spawned_at: 0
      })

      Creatures.put_wild_creature("test:2", %{
        type: :frost_shard,
        face: @test_face,
        row: 2,
        col: 2,
        spawned_at: 0
      })

      by_face = Creatures.creatures_by_face()
      assert length(Map.get(by_face, @test_face, [])) == 2
    end
  end

  describe "maybe_spawn/2" do
    test "spawns creatures on correct tick interval" do
      # Try multiple spawn intervals since random placement may miss valid tiles
      spawned =
        Enum.flat_map(1..10, fn i ->
          Creatures.maybe_spawn(25 * i, 42)
        end)

      assert length(spawned) > 0
    end

    test "does not spawn on non-interval ticks" do
      spawned = Creatures.maybe_spawn(1, 42)
      assert spawned == []
    end
  end

  describe "move_creatures/1" do
    test "moves creatures on correct tick interval" do
      Creatures.put_wild_creature("test:move", %{
        type: :ember_wisp,
        face: 0,
        row: 5,
        col: 5,
        spawned_at: 0
      })

      # Should move on tick 5 (move interval)
      moved = Creatures.move_creatures(5)
      assert length(moved) > 0
    end

    test "does not move on non-interval ticks" do
      Creatures.put_wild_creature("test:nomove", %{
        type: :ember_wisp,
        face: 0,
        row: 5,
        col: 5,
        spawned_at: 0
      })

      moved = Creatures.move_creatures(1)
      assert moved == []
    end
  end

  describe "player roster" do
    test "starts empty" do
      assert Creatures.get_player_roster("player:test") == []
    end

    test "capture_creature adds to roster" do
      creature = %{type: :ember_wisp, face: @test_face, row: 5, col: 5, spawned_at: 0}
      Creatures.put_wild_creature("test:cap", creature)

      Creatures.capture_creature("test:cap", creature, "player:test")

      roster = Creatures.get_player_roster("player:test")
      assert length(roster) == 1
      assert hd(roster).type == :ember_wisp
      assert hd(roster).id == "test:cap"

      # Should be removed from wild
      assert Creatures.get_wild_creature("test:cap") == nil
    end

    test "put_player_roster stores roster" do
      roster = [
        %{id: "c1", type: :ember_wisp, assigned_to: nil, captured_at: 100},
        %{id: "c2", type: :frost_shard, assigned_to: nil, captured_at: 200}
      ]

      Creatures.put_player_roster("player:test", roster)
      assert Creatures.get_player_roster("player:test") == roster
    end
  end

  describe "assign_creature/3" do
    setup do
      creature = %{type: :ember_wisp, face: @test_face, row: 5, col: 5, spawned_at: 0}
      Creatures.put_wild_creature("test:assign", creature)
      Creatures.capture_creature("test:assign", creature, "player:test")

      building = %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5},
        owner_id: "player:test"
      }

      WorldStore.put_building({@test_face, 3, 3}, building)
      :ok
    end

    test "assigns creature to building" do
      assert :ok == Creatures.assign_creature("player:test", "test:assign", {@test_face, 3, 3})

      roster = Creatures.get_player_roster("player:test")
      assigned = Enum.find(roster, fn c -> c.id == "test:assign" end)
      assert assigned.assigned_to == {@test_face, 3, 3}
    end

    test "rejects assignment to non-owned building" do
      building = %{
        type: :miner,
        orientation: 0,
        state: %{},
        owner_id: "player:other"
      }

      WorldStore.put_building({@test_face, 4, 4}, building)

      assert {:error, :not_owner} ==
               Creatures.assign_creature("player:test", "test:assign", {@test_face, 4, 4})
    end

    test "rejects assignment to conveyor" do
      building = %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil},
        owner_id: "player:test"
      }

      WorldStore.put_building({@test_face, 5, 5}, building)

      assert {:error, :invalid_building_type} ==
               Creatures.assign_creature("player:test", "test:assign", {@test_face, 5, 5})
    end

    test "rejects assignment when creature not found" do
      assert {:error, :creature_not_found} ==
               Creatures.assign_creature("player:test", "nonexistent", {@test_face, 3, 3})
    end
  end

  describe "unassign_creature/2" do
    test "unassigns creature from building" do
      creature = %{type: :frost_shard, face: @test_face, row: 1, col: 1, spawned_at: 0}
      Creatures.put_wild_creature("test:unassign", creature)
      Creatures.capture_creature("test:unassign", creature, "player:test")

      building = %{
        type: :smelter,
        orientation: 0,
        state: %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10},
        owner_id: "player:test"
      }

      WorldStore.put_building({@test_face, 6, 6}, building)
      Creatures.assign_creature("player:test", "test:unassign", {@test_face, 6, 6})

      assert :ok == Creatures.unassign_creature("player:test", "test:unassign")

      roster = Creatures.get_player_roster("player:test")
      unassigned = Enum.find(roster, fn c -> c.id == "test:unassign" end)
      assert unassigned.assigned_to == nil
    end
  end

  describe "boosted_rate/2" do
    test "returns base rate when no creature assigned" do
      assert Creatures.boosted_rate({@test_face, 9, 9}, 10) == 10
    end

    test "reduces rate when speed creature assigned" do
      creature = %{type: :ember_wisp, face: @test_face, row: 1, col: 1, spawned_at: 0}
      Creatures.put_wild_creature("test:boost", creature)
      Creatures.capture_creature("test:boost", creature, "player:boost")

      building = %{
        type: :miner,
        orientation: 0,
        state: %{output_buffer: nil, progress: 0, rate: 5},
        owner_id: "player:boost"
      }

      WorldStore.put_building({@test_face, 7, 7}, building)
      Creatures.assign_creature("player:boost", "test:boost", {@test_face, 7, 7})

      # Ember Wisp: speed +40%, so rate 10 * 0.6 = 6
      boosted = Creatures.boosted_rate({@test_face, 7, 7}, 10)
      assert boosted == 6
    end
  end

  describe "has_assigned_creature?/1" do
    test "returns false when no creature assigned" do
      refute Creatures.has_assigned_creature?({@test_face, 8, 8})
    end

    test "returns true when creature assigned" do
      creature = %{type: :copper_beetle, face: @test_face, row: 1, col: 1, spawned_at: 0}
      Creatures.put_wild_creature("test:has", creature)
      Creatures.capture_creature("test:has", creature, "player:has")

      building = %{
        type: :smelter,
        orientation: 0,
        state: %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10},
        owner_id: "player:has"
      }

      WorldStore.put_building({@test_face, 8, 8}, building)
      Creatures.assign_creature("player:has", "test:has", {@test_face, 8, 8})

      assert Creatures.has_assigned_creature?({@test_face, 8, 8})
    end
  end
end
