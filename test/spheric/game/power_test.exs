defmodule Spheric.Game.PowerTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.{Power, WorldStore}

  # Use face 29 (within the 0..29 range that Power.resolve scans)
  @test_face 29

  setup do
    Power.init()
    Power.clear()

    on_exit(fn ->
      Power.clear()
      # Clean up test buildings
      for r <- 0..20, c <- 0..20 do
        if WorldStore.has_building?({@test_face, r, c}) do
          WorldStore.remove_building({@test_face, r, c})
        end
      end
    end)

    :ok
  end

  describe "powered?/1" do
    test "returns false when nothing is powered" do
      refute Power.powered?({@test_face, 5, 5})
    end

    test "returns false for nonexistent buildings" do
      refute Power.powered?({99, 99, 99})
    end
  end

  describe "resolve/0 with no generators" do
    test "leaves everything unpowered" do
      # Place a substation but no generator
      WorldStore.put_building({@test_face, 5, 5}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      Power.resolve()

      refute Power.powered?({@test_face, 5, 5})
    end
  end

  describe "resolve/0 with fueled generator" do
    test "powers a nearby substation" do
      # Generator at (3,3)
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 100, fuel_type: :biofuel, power_output: 1},
        owner_id: "player:test"
      })

      # Substation at (3,5) — within radius 3 of generator
      WorldStore.put_building({@test_face, 3, 5}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      Power.resolve()

      assert Power.powered?({@test_face, 3, 5})
    end

    test "does not power distant substation beyond generator radius" do
      # Generator at (3,3)
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 100, fuel_type: :biofuel, power_output: 1},
        owner_id: "player:test"
      })

      # Substation at (3,15) — far beyond radius 3
      WorldStore.put_building({@test_face, 3, 15}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      Power.resolve()

      refute Power.powered?({@test_face, 3, 15})
    end

    test "powers machines within substation radius" do
      # Generator at (3,3)
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 100, fuel_type: :biofuel, power_output: 1},
        owner_id: "player:test"
      })

      # Substation at (3,5) — within gen radius
      WorldStore.put_building({@test_face, 3, 5}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      # Smelter at (3,7) — within substation radius 4
      WorldStore.put_building({@test_face, 3, 7}, %{
        type: :smelter,
        orientation: 0,
        state: %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10},
        owner_id: "player:test"
      })

      Power.resolve()

      assert Power.powered?({@test_face, 3, 7})
    end
  end

  describe "resolve/0 with unfueled generator" do
    test "does not power anything" do
      # Generator with no fuel
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 0, fuel_type: nil, power_output: 0},
        owner_id: "player:test"
      })

      WorldStore.put_building({@test_face, 3, 5}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      Power.resolve()

      refute Power.powered?({@test_face, 3, 3})
      refute Power.powered?({@test_face, 3, 5})
    end
  end

  describe "resolve/0 substation chaining" do
    test "chains power through connected substations" do
      # Generator at (3,3)
      WorldStore.put_building({@test_face, 3, 3}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 100, fuel_type: :biofuel, power_output: 1},
        owner_id: "player:test"
      })

      # Substation at (3,5) — within gen radius 3
      WorldStore.put_building({@test_face, 3, 5}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      # Substation at (3,9) — within first substation's radius (distance 4)
      WorldStore.put_building({@test_face, 3, 9}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      Power.resolve()

      assert Power.powered?({@test_face, 3, 5})
      assert Power.powered?({@test_face, 3, 9})
    end
  end

  describe "maybe_resolve/1" do
    test "only resolves every 5 ticks" do
      # Place a powered setup: generator + substation
      WorldStore.put_building({@test_face, 10, 10}, %{
        type: :bio_generator,
        orientation: 0,
        state: %{fuel_remaining: 100, fuel_type: :biofuel, power_output: 1},
        owner_id: "player:test"
      })

      WorldStore.put_building({@test_face, 10, 12}, %{
        type: :substation,
        orientation: 0,
        state: %{radius: 4, active: true},
        owner_id: "player:test"
      })

      # Tick 1: should NOT resolve (rem(1,5) != 0)
      Power.maybe_resolve(1)
      refute Power.powered?({@test_face, 10, 12})

      # Tick 5: should resolve (rem(5,5) == 0)
      Power.maybe_resolve(5)
      assert Power.powered?({@test_face, 10, 12})
    end
  end
end
