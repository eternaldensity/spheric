defmodule SphericWeb.GameLive.CameraEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Geometry.Coordinate
  alias Spheric.Game.{ShiftCycle, WorldStore}
  alias SphericWeb.Presence

  @presence_topic "game:presence"

  def handle_event("camera_update", %{"x" => x, "y" => y, "z" => z}, socket) do
    camera_pos = {x, y, z}
    visible = Coordinate.visible_faces(camera_pos) |> MapSet.new()

    # Dynamic face subscriptions: subscribe to new, unsubscribe from old
    old_faces = socket.assigns.subscribed_faces
    new_faces = visible
    to_subscribe = MapSet.difference(new_faces, old_faces)
    to_unsubscribe = MapSet.difference(old_faces, new_faces)

    for face_id <- MapSet.to_list(to_subscribe) do
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:face:#{face_id}")
    end

    for face_id <- MapSet.to_list(to_unsubscribe) do
      Phoenix.PubSub.unsubscribe(Spheric.PubSub, "world:face:#{face_id}")
    end

    # Update presence with new camera position
    Presence.update(self(), @presence_topic, socket.assigns.player_id, fn meta ->
      Map.put(meta, :camera, %{x: x, y: y, z: z})
    end)

    # Recompute local lighting for the new camera direction
    local = ShiftCycle.lighting_for_camera(camera_pos)

    socket =
      socket
      |> assign(:camera_pos, camera_pos)
      |> assign(:visible_faces, visible)
      |> assign(:subscribed_faces, new_faces)
      |> assign(:shift_phase, local.phase)
      |> push_event("local_lighting", %{
        phase: Atom.to_string(local.phase),
        ambient: local.ambient,
        intensity: local.intensity,
        bg: local.bg
      })

    # Auto-refuel: when zoomed close, check nearby drone bays with fuel buffer
    height = :math.sqrt(x * x + y * y + z * z) - 1.0

    socket =
      if height < 0.5 do
        try_auto_refuel(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  defp try_auto_refuel(socket) do
    player_id = socket.assigns.player_id

    # Check drone bays on visible faces only
    result =
      socket.assigns.visible_faces
      |> Enum.flat_map(fn face_id -> WorldStore.get_face_buildings(face_id) end)
      |> Enum.find(fn {_key, b} ->
        b.type == :drone_bay &&
          b.owner_id == player_id &&
          b.state[:auto_refuel_enabled] == true &&
          is_list(b.state[:fuel_buffer]) &&
          length(b.state[:fuel_buffer]) > 0
      end)

    case result do
      {key, building} ->
        [fuel_item | rest] = building.state.fuel_buffer
        new_state = %{building.state | fuel_buffer: rest}
        WorldStore.put_building(key, %{building | state: new_state})

        push_event(socket, "fuel_pickup_result", %{
          success: true,
          item: Atom.to_string(fuel_item)
        })

      nil ->
        socket
    end
  end
end
