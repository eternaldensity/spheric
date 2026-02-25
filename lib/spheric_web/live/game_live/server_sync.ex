defmodule SphericWeb.GameLive.ServerSync do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.{
    Creatures,
    AlteredItems,
    Hiss,
    Territory,
    TheBoard,
    ShiftCycle
  }

  alias SphericWeb.GameLive.Helpers
  alias SphericWeb.Presence

  @presence_topic "game:presence"

  # --- Building Handlers ---

  def handle_info({:building_placed, {face, row, col}, building}, socket) do
    payload = %{
      face: face,
      row: row,
      col: col,
      type: Atom.to_string(building.type),
      orientation: building.orientation
    }

    payload =
      case building.state do
        %{construction: %{complete: false}} -> Map.put(payload, :under_construction, true)
        _ -> payload
      end

    socket = push_event(socket, "building_placed", payload)
    {:noreply, socket}
  end

  def handle_info({:building_removed, {face, row, col}}, socket) do
    socket = push_event(socket, "building_removed", %{face: face, row: row, col: col})
    {:noreply, socket}
  end

  def handle_info({:construction_complete, {face, row, col}, building}, socket) do
    socket =
      push_event(socket, "construction_complete", %{
        face: face,
        row: row,
        col: col,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      })

    {:noreply, socket}
  end

  def handle_info({:tick_update, tick, face_id, items}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      serialized_items =
        Enum.map(items, fn item ->
          %{
            row: item.row,
            col: item.col,
            item: Atom.to_string(item.item),
            speed: item[:speed] || 1,
            from_face: item.from_face,
            from_row: item.from_row,
            from_col: item.from_col
          }
        end)

      socket =
        push_event(socket, "tick_items", %{
          tick: tick,
          face: face_id,
          items: serialized_items
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Drone Upgrade Handlers ---

  def handle_info({:drone_upgrade_complete, _key, upgrade, _player_id}, socket) do
    socket =
      push_event(socket, "drone_upgrade_granted", %{
        upgrade: Atom.to_string(upgrade)
      })

    # Refresh tile info if currently viewing this building
    socket =
      if socket.assigns[:tile_info] && socket.assigns.tile_info[:building] &&
           socket.assigns.tile_info.building.type == :drone_bay do
        key = {socket.assigns.tile_info.face, socket.assigns.tile_info.row, socket.assigns.tile_info.col}
        assign(socket, :tile_info, Helpers.build_tile_info(key))
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Research Handlers ---

  def handle_info({:case_file_completed, _case_file_id}, socket) do
    Helpers.refresh_research(socket)
  end

  def handle_info({:research_progress, _item}, socket) do
    Helpers.refresh_research(socket)
  end

  def handle_info({:object_of_power_granted, _object}, socket) do
    objects = Spheric.Game.ObjectsOfPower.player_objects(socket.assigns.player_id)
    {:noreply, assign(socket, :objects_of_power, objects)}
  end

  # --- Creature Handlers ---

  def handle_info({:creature_spawned, id, creature}, socket) do
    socket =
      push_event(socket, "creature_spawned", %{
        id: id,
        creature: %{
          type: Atom.to_string(creature.type),
          face: creature.face,
          row: creature.row,
          col: creature.col
        }
      })

    {:noreply, socket}
  end

  def handle_info({:creature_moved, id, creature}, socket) do
    socket =
      push_event(socket, "creature_moved", %{
        id: id,
        creature: %{
          type: Atom.to_string(creature.type),
          face: creature.face,
          row: creature.row,
          col: creature.col
        }
      })

    {:noreply, socket}
  end

  def handle_info({:creature_captured, creature_id, _creature, _trap_key}, socket) do
    socket = push_event(socket, "creature_captured", %{id: creature_id})
    roster = Creatures.get_player_roster(socket.assigns.player_id)
    {:noreply, assign(socket, :creature_roster, roster)}
  end

  def handle_info({:creature_sync, face_id, creatures}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      serialized =
        Enum.map(creatures, fn c ->
          %{id: c.id, type: Atom.to_string(c.type), face: c.face, row: c.row, col: c.col}
        end)

      socket = push_event(socket, "creature_sync", %{face: face_id, creatures: serialized})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Hiss Corruption Handlers ---

  def handle_info({:corruption_update, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_update", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:corruption_cleared, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_cleared", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:corruption_sync, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_sync", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:hiss_spawned, id, entity}, socket) do
    socket =
      push_event(socket, "hiss_spawned", %{
        id: id,
        entity: %{face: entity.face, row: entity.row, col: entity.col, health: entity.health}
      })

    {:noreply, socket}
  end

  def handle_info({:hiss_moved, id, entity}, socket) do
    socket =
      push_event(socket, "hiss_moved", %{
        id: id,
        entity: %{face: entity.face, row: entity.row, col: entity.col, health: entity.health}
      })

    {:noreply, socket}
  end

  def handle_info({:hiss_killed, id, _killer}, socket) do
    socket = push_event(socket, "hiss_killed", %{id: id})
    {:noreply, socket}
  end

  def handle_info({:hiss_sync, face_id, entities}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "hiss_sync", %{face: face_id, entities: entities})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:building_damage, {face, row, col}, action}, socket) do
    socket =
      push_event(socket, "building_damaged", %{
        face: face,
        row: row,
        col: col,
        action: Atom.to_string(action)
      })

    socket =
      if action == :destroyed and socket.assigns.selected_tile do
        sel = socket.assigns.selected_tile

        if sel.face == face and sel.row == row and sel.col == col do
          assign(socket, :tile_info, Helpers.build_tile_info({face, row, col}))
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Territory Handlers ---

  def handle_info({:territory_update, face_id, territories}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket =
        push_event(socket, "territory_update", %{face: face_id, territories: territories})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- World Events, Shift Cycle, Creature Evolution ---

  def handle_info({:world_event_started, event_type, event_info}, socket) do
    messages =
      TheBoard.check_milestones(socket.assigns.player_id, %{first_world_event: true})

    socket =
      socket
      |> assign(:active_event, event_type)
      |> push_event("world_event_started", %{
        event: Atom.to_string(event_type),
        name: event_info.name,
        color: event_info.color
      })
      |> then(fn s ->
        case messages do
          [{_milestone, msg} | _] -> assign(s, :board_message, msg)
          _ -> s
        end
      end)

    {:noreply, socket}
  end

  def handle_info({:world_event_ended, event_type}, socket) do
    socket =
      socket
      |> assign(:active_event, nil)
      |> push_event("world_event_ended", %{event: Atom.to_string(event_type)})

    {:noreply, socket}
  end

  def handle_info({:shift_cycle_changed, _phase, _lighting, _modifiers, sun_dir}, socket) do
    {sx, sy, sz} = sun_dir
    local = ShiftCycle.lighting_for_camera(socket.assigns.camera_pos)

    socket =
      socket
      |> assign(:shift_phase, local.phase)
      |> push_event("shift_cycle_changed", %{
        phase: Atom.to_string(local.phase),
        ambient: local.ambient,
        directional: local.directional,
        intensity: local.intensity,
        bg: local.bg,
        sun_x: sx,
        sun_y: sy,
        sun_z: sz
      })

    {:noreply, socket}
  end

  def handle_info({:sun_moved, sun_dir}, socket) do
    {sx, sy, sz} = sun_dir
    local = ShiftCycle.lighting_for_camera(socket.assigns.camera_pos)

    socket =
      socket
      |> assign(:shift_phase, local.phase)
      |> push_event("sun_moved", %{
        sun_x: sx,
        sun_y: sy,
        sun_z: sz,
        phase: Atom.to_string(local.phase),
        ambient: local.ambient,
        intensity: local.intensity,
        bg: local.bg
      })

    {:noreply, socket}
  end

  def handle_info({:creature_evolved, player_id, _creature_id, _creature}, socket) do
    if player_id == socket.assigns.player_id do
      messages =
        TheBoard.check_milestones(socket.assigns.player_id, %{creature_evolved: true})

      roster = Creatures.get_player_roster(socket.assigns.player_id)

      socket =
        socket
        |> assign(:creature_roster, roster)
        |> then(fn s ->
          case messages do
            [{_milestone, msg} | _] -> assign(s, :board_message, msg)
            _ -> s
          end
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Terrain Streaming ---

  def handle_info(:send_terrain, socket) do
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    socket =
      Enum.reduce(0..29, socket, fn face_id, sock ->
        terrain = Helpers.build_face_terrain(face_id, subdivisions)

        altered =
          AlteredItems.get_face_items(face_id)
          |> Enum.map(fn {{_f, row, col}, type_id} ->
            info = AlteredItems.get_type(type_id)
            %{row: row, col: col, type: Atom.to_string(type_id), color: info.color}
          end)

        corruption = Hiss.corrupted_on_face(face_id)

        hiss_entities =
          Hiss.hiss_entities_on_face(face_id)
          |> Enum.map(fn {id, e} ->
            %{id: id, face: e.face, row: e.row, col: e.col, health: e.health}
          end)

        territories = Territory.territories_on_face(face_id)

        sock
        |> push_event("terrain_face", %{face: face_id, terrain: terrain})
        |> push_event("altered_items", %{face: face_id, items: altered})
        |> push_event("corruption_sync", %{face: face_id, tiles: corruption})
        |> push_event("hiss_sync", %{face: face_id, entities: hiss_entities})
        |> push_event("territory_sync", %{face: face_id, territories: territories})
      end)

    {:noreply, socket}
  end

  # --- Presence Handlers ---

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    players =
      Presence.list(@presence_topic)
      |> Enum.reject(fn {id, _} -> id == socket.assigns.player_id end)
      |> Enum.map(fn {_id, %{metas: [meta | _]}} ->
        %{
          name: meta.name,
          color: meta.color,
          x: meta.camera.x,
          y: meta.camera.y,
          z: meta.camera.z
        }
      end)

    socket = push_event(socket, "players_update", %{players: players})
    {:noreply, socket}
  end

  # --- Admin Handlers ---

  def handle_info(:world_reset, socket) do
    socket = push_event(socket, "world_reset", %{})
    {:noreply, socket}
  end
end
