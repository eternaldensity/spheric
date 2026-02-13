defmodule Spheric.Game.DirtyTrackingTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.WorldStore

  # Use high face IDs to avoid collision with the running world (faces 0-29)
  @test_face 70

  setup do
    # Clear any pre-existing dirty state
    WorldStore.drain_dirty()
    :ok
  end

  test "put_tile marks tile as dirty" do
    WorldStore.put_tile({@test_face, 0, 0}, %{terrain: :grassland, resource: nil})

    {tiles, _, _} = WorldStore.drain_dirty()
    assert {70, 0, 0} in tiles
  end

  test "put_building marks building as dirty" do
    WorldStore.put_building({@test_face, 1, 1}, %{
      type: :conveyor,
      orientation: 0,
      state: %{item: nil}
    })

    {_, buildings, _} = WorldStore.drain_dirty()
    assert {70, 1, 1} in buildings

    # Cleanup
    WorldStore.remove_building({@test_face, 1, 1})
    WorldStore.drain_dirty()
  end

  test "remove_building marks as removed and clears building dirty" do
    WorldStore.put_building({@test_face, 2, 2}, %{type: :miner, orientation: 0, state: %{}})
    # Clear the put_building dirty marker
    WorldStore.drain_dirty()

    WorldStore.remove_building({@test_face, 2, 2})

    {_, buildings, removed} = WorldStore.drain_dirty()
    assert {70, 2, 2} in removed
    refute {70, 2, 2} in buildings
  end

  test "put_building clears a previous building_removed marker" do
    WorldStore.put_building({@test_face, 3, 3}, %{
      type: :conveyor,
      orientation: 0,
      state: %{item: nil}
    })

    WorldStore.drain_dirty()

    WorldStore.remove_building({@test_face, 3, 3})
    # Now re-place a building at the same spot
    WorldStore.put_building({@test_face, 3, 3}, %{type: :smelter, orientation: 1, state: %{}})

    {_, buildings, removed} = WorldStore.drain_dirty()
    assert {70, 3, 3} in buildings
    refute {70, 3, 3} in removed

    # Cleanup
    WorldStore.remove_building({@test_face, 3, 3})
    WorldStore.drain_dirty()
  end

  test "put_tiles (batch) does NOT mark dirty" do
    WorldStore.put_tiles([
      {{@test_face, 4, 0}, %{terrain: :desert, resource: nil}},
      {{@test_face, 4, 1}, %{terrain: :forest, resource: nil}}
    ])

    {tiles, _, _} = WorldStore.drain_dirty()
    refute {70, 4, 0} in tiles
    refute {70, 4, 1} in tiles
  end

  test "drain_dirty clears the dirty table" do
    WorldStore.put_tile({@test_face, 5, 5}, %{terrain: :tundra, resource: nil})
    WorldStore.drain_dirty()

    # Second drain should not contain our key
    {tiles, _, _} = WorldStore.drain_dirty()
    refute {70, 5, 5} in tiles
  end

  test "dirty_count reflects pending changes" do
    initial = WorldStore.dirty_count()

    WorldStore.put_tile({@test_face, 6, 0}, %{terrain: :volcanic, resource: nil})

    WorldStore.put_building({@test_face, 6, 1}, %{
      type: :conveyor,
      orientation: 0,
      state: %{item: nil}
    })

    assert WorldStore.dirty_count() >= initial + 2

    WorldStore.drain_dirty()
    WorldStore.remove_building({@test_face, 6, 1})
    WorldStore.drain_dirty()
  end
end
