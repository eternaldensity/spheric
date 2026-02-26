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
      for r <- 0..30, c <- 0..30 do
        if WorldStore.has_building?({@test_face, r, c}) do
          WorldStore.remove_building({@test_face, r, c})
        end
      end
    end)

    :ok
  end

  defp place_generator(row, col, fuel_remaining \\ 100) do
    WorldStore.put_building({@test_face, row, col}, %{
      type: :bio_generator,
      orientation: 0,
      state: %{fuel_remaining: fuel_remaining, fuel_type: :biofuel, power_output: 20, rate: 1, powered: true, input_buffer: nil},
      owner_id: "player:test"
    })
  end

  defp place_substation(row, col) do
    WorldStore.put_building({@test_face, row, col}, %{
      type: :substation,
      orientation: 0,
      state: %{radius: 4, active: true},
      owner_id: "player:test"
    })
  end

  defp place_building(row, col, type, opts \\ []) do
    powered = Keyword.get(opts, :powered, true)
    under_construction = Keyword.get(opts, :under_construction, false)

    state =
      if under_construction do
        %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10, powered: powered,
          construction: %{complete: false, required: %{iron_ingot: 3}, delivered: %{iron_ingot: 0}}}
      else
        %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10, powered: powered}
      end

    WorldStore.put_building({@test_face, row, col}, %{
      type: type,
      orientation: 0,
      state: state,
      owner_id: "player:test"
    })
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
      place_substation(5, 5)
      Power.resolve()
      refute Power.powered?({@test_face, 5, 5})
    end
  end

  describe "resolve/0 with fueled generator" do
    test "powers a nearby substation" do
      place_generator(3, 3)
      place_substation(3, 5)
      Power.resolve()
      assert Power.powered?({@test_face, 3, 5})
    end

    test "does not power distant substation beyond generator radius" do
      place_generator(3, 3)
      place_substation(3, 15)
      Power.resolve()
      refute Power.powered?({@test_face, 3, 15})
    end

    test "powers machines within substation radius" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 7, :smelter)
      Power.resolve()
      assert Power.powered?({@test_face, 3, 7})
    end
  end

  describe "resolve/0 with unfueled generator" do
    test "does not power anything" do
      place_generator(3, 3, 0)
      place_substation(3, 5)
      Power.resolve()
      refute Power.powered?({@test_face, 3, 3})
      refute Power.powered?({@test_face, 3, 5})
    end
  end

  describe "resolve/0 substation chaining" do
    test "chains power through connected substations" do
      place_generator(3, 3)
      place_substation(3, 5)
      # Second substation within radius 4 of first
      place_substation(3, 9)
      Power.resolve()
      assert Power.powered?({@test_face, 3, 5})
      assert Power.powered?({@test_face, 3, 9})
    end
  end

  describe "maybe_resolve/1" do
    test "only resolves every 5 ticks" do
      place_generator(10, 10)
      place_substation(10, 12)

      # Tick 1: should NOT resolve (rem(1,5) != 0)
      Power.maybe_resolve(1)
      refute Power.powered?({@test_face, 10, 12})

      # Tick 5: should resolve (rem(5,5) == 0)
      Power.maybe_resolve(5)
      assert Power.powered?({@test_face, 10, 12})
    end
  end

  describe "network_stats/1" do
    test "returns nil for disconnected building" do
      place_building(5, 5, :smelter)
      Power.resolve()
      assert Power.network_stats({@test_face, 5, 5}) == nil
    end

    test "returns capacity and load for a connected building" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 7, :smelter)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 7})
      assert stats != nil
      assert stats.capacity == 20
      # smelter draws 2W
      assert stats.load == 2
    end

    test "sums multiple generators in same network" do
      place_generator(3, 3)
      place_generator(3, 5)
      place_substation(3, 4)
      place_building(3, 6, :assembler)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 6})
      assert stats.capacity == 40
    end

    test "sums multiple building draws" do
      place_generator(3, 3)
      place_substation(3, 5)
      # 3 smelters at 2W each = 6W
      place_building(3, 6, :smelter)
      place_building(3, 7, :smelter)
      place_building(3, 8, :smelter)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 6})
      assert stats.load == 6
    end

    test "excludes powered-off buildings from load" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 6, :smelter)
      place_building(3, 7, :smelter, powered: false)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 6})
      # Only the powered-on smelter counts
      assert stats.load == 2
    end

    test "excludes buildings under construction from load" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 6, :smelter)
      place_building(3, 7, :smelter, under_construction: true)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 6})
      assert stats.load == 2
    end

    test "zero-draw buildings do not contribute to load" do
      place_generator(3, 3)
      place_substation(3, 5)
      # conveyor has 0W draw
      WorldStore.put_building({@test_face, 3, 7}, %{
        type: :conveyor,
        orientation: 0,
        state: %{item: nil, move_ticks: 0},
        owner_id: "player:test"
      })
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 7})
      assert stats.load == 0
    end
  end

  describe "load_ratio/1" do
    test "returns nil for disconnected building" do
      place_building(5, 5, :smelter)
      Power.resolve()
      assert Power.load_ratio({@test_face, 5, 5}) == nil
    end

    test "returns 1.0 when capacity exceeds load" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 7, :smelter)
      Power.resolve()

      assert Power.load_ratio({@test_face, 3, 7}) == 1.0
    end

    test "returns ratio > 1.0 when overloaded" do
      place_generator(3, 3)
      place_substation(3, 5)
      # Place enough buildings to exceed 20W capacity
      # 3 advanced_smelters at 8W = 24W, capacity 20W
      place_building(3, 6, :advanced_smelter)
      place_building(3, 7, :advanced_smelter)
      place_building(3, 8, :advanced_smelter)
      Power.resolve()

      ratio = Power.load_ratio({@test_face, 3, 6})
      assert ratio > 1.0
      assert_in_delta ratio, 24 / 20, 0.01
    end
  end

  describe "separate networks" do
    test "disconnected substation clusters have independent stats" do
      # Network A: generator at (3,3), substation at (3,5), smelter at (3,7)
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 7, :smelter)

      # Network B: generator at (3,20), substation at (3,22), assembler at (3,24)
      place_generator(3, 20)
      place_substation(3, 22)
      place_building(3, 24, :assembler)

      Power.resolve()

      stats_a = Power.network_stats({@test_face, 3, 7})
      stats_b = Power.network_stats({@test_face, 3, 24})

      assert stats_a != nil
      assert stats_b != nil
      # Network A: 20W capacity, 2W load (smelter)
      assert stats_a.capacity == 20
      assert stats_a.load == 2
      # Network B: 20W capacity, 2W load (assembler)
      assert stats_b.capacity == 20
      assert stats_b.load == 2
    end

    test "cross-face buildings are never in same network" do
      place_generator(3, 3)
      place_substation(3, 5)

      # Building on different face at same coordinates
      other_face = 28
      WorldStore.put_building({other_face, 3, 7}, %{
        type: :smelter,
        orientation: 0,
        state: %{input_buffer: nil, output_buffer: nil, progress: 0, rate: 10, powered: true},
        owner_id: "player:test"
      })

      Power.resolve()

      assert Power.powered?({@test_face, 3, 5})
      refute Power.powered?({other_face, 3, 7})

      on_exit(fn ->
        if WorldStore.has_building?({other_face, 3, 7}) do
          WorldStore.remove_building({other_face, 3, 7})
        end
      end)
    end
  end

  describe "generator network stats" do
    test "generator itself shows network stats" do
      place_generator(3, 3)
      place_substation(3, 5)
      place_building(3, 7, :smelter)
      Power.resolve()

      stats = Power.network_stats({@test_face, 3, 3})
      assert stats != nil
      assert stats.capacity == 20
    end
  end
end
