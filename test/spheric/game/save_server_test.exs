defmodule Spheric.Game.SaveServerTest do
  use Spheric.DataCase, async: false

  alias Spheric.Game.{SaveServer, WorldStore, Persistence}
  alias Spheric.Game.Schema.{World, Building}

  # Use high face IDs to avoid collision with the running world
  @test_face 55

  setup do
    Repo.delete_all(World)

    on_exit(fn ->
      if WorldStore.has_building?({@test_face, 0, 0}) do
        WorldStore.remove_building({@test_face, 0, 0})
      end

      WorldStore.drain_dirty()
    end)

    :ok
  end

  test "save_now persists dirty buildings to database" do
    world = Persistence.ensure_world("test_save_server", 42, 16)
    SaveServer.set_world(world.id)

    # Place a building in ETS (this marks it dirty)
    WorldStore.put_building({@test_face, 0, 0}, %{
      type: :conveyor,
      orientation: 0,
      state: %{item: nil}
    })

    # Trigger immediate save
    SaveServer.save_now()

    # Verify it's in the database
    b = Repo.get_by(Building, world_id: world.id, face_id: @test_face, row: 0, col: 0)
    assert b
    assert b.type == "conveyor"
  end

  test "save_now with no dirty state is a no-op" do
    world = Persistence.ensure_world("test_noop", 42, 16)
    SaveServer.set_world(world.id)

    # Drain any pre-existing dirty state
    WorldStore.drain_dirty()

    # Should succeed without error
    assert :ok = SaveServer.save_now()
  end
end
