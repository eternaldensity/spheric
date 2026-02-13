defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Geometry.Coordinate
  alias Spheric.Game.{WorldServer, WorldStore, Buildings, Persistence}
  alias SphericWeb.Presence

  require Logger

  @presence_topic "game:presence"

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()

    # Build initial buildings snapshot
    buildings_data = build_buildings_snapshot()

    # Initial face set: all faces (until first camera_update narrows it)
    initial_faces = MapSet.new(0..29)

    # Subscribe to face PubSub topics and presence
    if connected?(socket) do
      for face_id <- MapSet.to_list(initial_faces) do
        Phoenix.PubSub.subscribe(Spheric.PubSub, "world:face:#{face_id}")
      end

      Phoenix.PubSub.subscribe(Spheric.PubSub, @presence_topic)
    end

    # Restore player identity and camera from client localStorage (via connect params),
    # or generate fresh values for new players.
    {player_id, player_name, player_color, camera} =
      if connected?(socket) do
        restore_player(get_connect_params(socket))
      else
        {"player:temp", Presence.random_name(), Presence.random_color(),
         %{x: 0.0, y: 0.0, z: 3.5, tx: 0.0, ty: 0.0, tz: 0.0}}
      end

    # Persist player identity mapping (id -> name, color)
    if connected?(socket), do: Persistence.upsert_player(player_id, player_name, player_color)

    # Track presence (only when connected)
    if connected?(socket) do
      Presence.track(self(), @presence_topic, player_id, %{
        name: player_name,
        color: player_color,
        camera: %{x: camera.x, y: camera.y, z: camera.z}
      })
    end

    socket =
      socket
      |> assign(:page_title, "Spheric")
      |> assign(:geometry_data, geometry_data)
      |> assign(:selected_tile, nil)
      |> assign(:tile_info, nil)
      |> assign(:selected_building_type, nil)
      |> assign(:placement_orientation, 0)
      |> assign(:camera_pos, {camera.x, camera.y, camera.z})
      |> assign(:visible_faces, initial_faces)
      |> assign(:subscribed_faces, initial_faces)
      |> assign(:building_types, Buildings.types())
      |> assign(:line_mode, false)
      |> assign(:player_id, player_id)
      |> assign(:player_name, player_name)
      |> assign(:player_color, player_color)
      |> push_event("buildings_snapshot", %{buildings: buildings_data})

    # Tell the client to restore camera and persist any newly-generated identity
    socket =
      if connected?(socket) do
        socket = push_event(socket, "restore_player", %{
          player_id: player_id,
          player_name: player_name,
          player_color: player_color,
          camera: camera
        })

        # Stream terrain data per-face via push_event (too large for data-attribute at 64x64)
        send(self(), :send_terrain)

        socket
      else
        socket
      end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="game-container"
      phx-hook="GameRenderer"
      phx-update="ignore"
      phx-window-keydown="keydown"
      data-geometry={Jason.encode!(@geometry_data)}
      style="width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0;"
    >
    </div>

    <div
      id="player-info"
      style="position: fixed; top: 16px; right: 16px; background: rgba(0,0,0,0.7); color: #fff; padding: 6px 12px; border-radius: 6px; font-family: monospace; font-size: 12px; pointer-events: none; display: flex; align-items: center; gap: 6px;"
    >
      <span style={"display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #{@player_color};"}>
      </span>
      {@player_name}
    </div>

    <div
      :if={@tile_info}
      style="position: fixed; top: 16px; left: 16px; background: rgba(0,0,0,0.8); color: #fff; padding: 10px 14px; border-radius: 6px; font-family: monospace; font-size: 13px; line-height: 1.6; pointer-events: auto; min-width: 180px;"
    >
      <div style="color: #aaa; font-size: 11px; margin-bottom: 4px;">
        Face {@tile_info.face} &middot; Row {@tile_info.row} &middot; Col {@tile_info.col}
      </div>
      <div>
        Terrain: <span style="color: #8cd">{@tile_info.terrain}</span>
      </div>
      <div :if={@tile_info.resource}>
        Resource: <span style="color: #fc8">{@tile_info.resource_type}</span>
        ({@tile_info.resource_amount})
      </div>
      <div :if={@tile_info.resource == nil} style="color: #666;">
        No resources
      </div>
      <div
        :if={@tile_info.building}
        style="margin-top: 4px; border-top: 1px solid #444; padding-top: 4px;"
      >
        <div>
          Building: <span style="color: #fd4">{@tile_info.building_name}</span>
        </div>
        <div style="color: #aaa; font-size: 11px;">
          Orientation: {@tile_info.building_orientation} ({direction_label(
            @tile_info.building_orientation
          )})
        </div>
        <div :if={@tile_info.building_status} style="color: #aaa; font-size: 11px;">
          {@tile_info.building_status}
        </div>
        <div :if={@tile_info.building_owner_name} style="color: #aaa; font-size: 11px;">
          Built by: <span style="color: #9be">{@tile_info.building_owner_name}</span>
        </div>
        <button
          :if={@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id}
          phx-click="remove_building"
          phx-value-face={@tile_info.face}
          phx-value-row={@tile_info.row}
          phx-value-col={@tile_info.col}
          style="margin-top: 6px; padding: 4px 10px; border: 1px solid #a44; border-radius: 4px; background: rgba(170,68,68,0.3); color: #f88; cursor: pointer; font-family: monospace; font-size: 11px;"
        >
          Remove
        </button>
      </div>
      <div :if={@tile_info.building == nil} style="color: #666; margin-top: 4px;">
        No building
      </div>
    </div>

    <div style="position: fixed; bottom: 0; left: 0; right: 0; display: flex; justify-content: center; gap: 4px; padding: 12px; background: rgba(0,0,0,0.75); pointer-events: auto;">
      <button
        :for={type <- @building_types}
        phx-click="select_building"
        phx-value-type={type}
        style={"
          padding: 8px 16px;
          border: 2px solid #{if @selected_building_type == type, do: "#ffdd44", else: "#555"};
          border-radius: 6px;
          background: #{if @selected_building_type == type, do: "rgba(255,221,68,0.2)", else: "rgba(255,255,255,0.1)"};
          color: #{if @selected_building_type == type, do: "#ffdd44", else: "#ccc"};
          cursor: pointer;
          font-family: monospace;
          font-size: 13px;
          font-weight: #{if @selected_building_type == type, do: "bold", else: "normal"};
        "}
      >
        {Buildings.display_name(type)}
      </button>
      <div
        :if={@selected_building_type}
        style="display: flex; align-items: center; gap: 4px; margin-left: 8px; padding-left: 8px; border-left: 1px solid #555;"
      >
        <button
          phx-click="rotate_building"
          style="padding: 8px 12px; border: 2px solid #77aaff; border-radius: 6px; background: rgba(119,170,255,0.15); color: #aaddff; cursor: pointer; font-family: monospace; font-size: 13px;"
          title="Rotate (R key)"
        >
          {direction_label(@placement_orientation)}
        </button>
        <button
          phx-click="toggle_line_mode"
          style={"padding: 8px 12px; border: 2px solid #{if @line_mode, do: "#44ddff", else: "#77aaff"}; border-radius: 6px; background: #{if @line_mode, do: "rgba(68,221,255,0.25)", else: "rgba(119,170,255,0.15)"}; color: #{if @line_mode, do: "#44ddff", else: "#aaddff"}; cursor: pointer; font-family: monospace; font-size: 13px; font-weight: #{if @line_mode, do: "bold", else: "normal"};"}
          title="Line draw mode (L key)"
        >
          Line
        </button>
        <button
          phx-click="select_building"
          phx-value-type="none"
          style="padding: 8px 16px; border: 2px solid #888; border-radius: 6px; background: rgba(255,255,255,0.1); color: #aaa; cursor: pointer; font-family: monospace; font-size: 13px;"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("select_building", %{"type" => "none"}, socket) do
    socket =
      socket
      |> assign(:selected_building_type, nil)
      |> assign(:line_mode, false)
      |> push_event("placement_mode", %{type: nil, orientation: nil})
      |> push_event("line_mode", %{enabled: false})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_building", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if Buildings.valid_type?(type) do
      orientation = socket.assigns.placement_orientation

      socket =
        socket
        |> assign(:selected_building_type, type)
        |> push_event("placement_mode", %{type: type_str, orientation: orientation})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rotate_building", _params, socket) do
    new_orientation = rem(socket.assigns.placement_orientation + 3, 4)

    socket =
      socket
      |> assign(:placement_orientation, new_orientation)
      |> push_event("placement_mode", %{
        type: Atom.to_string(socket.assigns.selected_building_type),
        orientation: new_orientation
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_line_mode", _params, socket) do
    if socket.assigns.selected_building_type do
      new_line_mode = !socket.assigns.line_mode

      socket =
        socket
        |> assign(:line_mode, new_line_mode)
        |> push_event("line_mode", %{enabled: new_line_mode})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("place_line", %{"buildings" => buildings_list}, socket) do
    case socket.assigns.selected_building_type do
      nil ->
        {:noreply, socket}

      building_type ->
        owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

        placements =
          Enum.map(buildings_list, fn %{"face" => face, "row" => row, "col" => col, "orientation" => orientation} ->
            {{face, row, col}, building_type, orientation, owner}
          end)

        results = WorldServer.place_buildings(placements)

        socket =
          Enum.reduce(results, socket, fn
            {{face, row, col}, :ok}, sock ->
              building = WorldStore.get_building({face, row, col})

              push_event(sock, "building_placed", %{
                face: face,
                row: row,
                col: col,
                type: Atom.to_string(building.type),
                orientation: building.orientation
              })

            {{face, row, col}, {:error, reason}}, sock ->
              push_event(sock, "place_error", %{
                face: face,
                row: row,
                col: col,
                reason: Atom.to_string(reason)
              })
          end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("tile_click", %{"face" => face, "row" => row, "col" => col}, socket) do
    key = {face, row, col}
    tile = %{face: face, row: row, col: col}
    Logger.debug("Tile clicked: face=#{face} row=#{row} col=#{col}")

    case socket.assigns.selected_building_type do
      nil ->
        tile_info = build_tile_info(key)

        socket =
          socket
          |> assign(:selected_tile, tile)
          |> assign(:tile_info, tile_info)

        {:noreply, socket}

      building_type ->
        orientation = socket.assigns.placement_orientation

        owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

        case WorldServer.place_building(key, building_type, orientation, owner) do
          :ok ->
            building = WorldStore.get_building(key)
            tile_info = build_tile_info(key)

            socket =
              socket
              |> assign(:selected_tile, tile)
              |> assign(:tile_info, tile_info)
              |> push_event("building_placed", %{
                face: face,
                row: row,
                col: col,
                type: Atom.to_string(building.type),
                orientation: building.orientation
              })

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> push_event("place_error", %{
                face: face,
                row: row,
                col: col,
                reason: Atom.to_string(reason)
              })

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("remove_building", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = to_int(face)
    row = to_int(row)
    col = to_int(col)
    key = {face, row, col}

    case WorldServer.remove_building(key, socket.assigns.player_id) do
      :ok ->
        tile_info = build_tile_info(key)

        socket =
          socket
          |> assign(:tile_info, tile_info)
          |> push_event("building_removed", %{face: face, row: row, col: col})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "r"}, socket) do
    if socket.assigns.selected_building_type do
      new_orientation = rem(socket.assigns.placement_orientation + 3, 4)

      socket =
        socket
        |> assign(:placement_orientation, new_orientation)
        |> push_event("placement_mode", %{
          type: Atom.to_string(socket.assigns.selected_building_type),
          orientation: new_orientation
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "l"}, socket) do
    if socket.assigns.selected_building_type do
      new_line_mode = !socket.assigns.line_mode

      socket =
        socket
        |> assign(:line_mode, new_line_mode)
        |> push_event("line_mode", %{enabled: new_line_mode})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
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

    socket =
      socket
      |> assign(:camera_pos, camera_pos)
      |> assign(:visible_faces, visible)
      |> assign(:subscribed_faces, new_faces)

    {:noreply, socket}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:building_placed, {face, row, col}, building}, socket) do
    socket =
      push_event(socket, "building_placed", %{
        face: face,
        row: row,
        col: col,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:building_removed, {face, row, col}}, socket) do
    socket = push_event(socket, "building_removed", %{face: face, row: row, col: col})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tick_update, tick, face_id, items}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      serialized_items =
        Enum.map(items, fn item ->
          %{
            row: item.row,
            col: item.col,
            item: Atom.to_string(item.item),
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

  # --- Terrain Streaming ---

  @impl true
  def handle_info(:send_terrain, socket) do
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    socket =
      Enum.reduce(0..29, socket, fn face_id, sock ->
        terrain = build_face_terrain(face_id, subdivisions)
        push_event(sock, "terrain_face", %{face: face_id, terrain: terrain})
      end)

    {:noreply, socket}
  end

  # --- Presence Handlers ---

  @impl true
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

  # --- Helpers ---

  defp build_face_terrain(face_id, subdivisions) do
    for row <- 0..(subdivisions - 1) do
      for col <- 0..(subdivisions - 1) do
        tile = WorldStore.get_tile({face_id, row, col})

        resource_type =
          case tile.resource do
            nil -> nil
            {type, _amount} -> Atom.to_string(type)
          end

        %{t: Atom.to_string(tile.terrain), r: resource_type}
      end
    end
  end

  defp direction_label(0), do: "W"
  defp direction_label(1), do: "S"
  defp direction_label(2), do: "E"
  defp direction_label(3), do: "N"

  defp build_tile_info({face, row, col} = key) do
    tile = WorldStore.get_tile(key)
    building = WorldStore.get_building(key)

    {resource_type, resource_amount} =
      case tile do
        %{resource: {type, amount}} -> {Atom.to_string(type), amount}
        _ -> {nil, nil}
      end

    base = %{
      face: face,
      row: row,
      col: col,
      terrain: Atom.to_string(tile.terrain),
      resource: tile.resource,
      resource_type: resource_type,
      resource_amount: resource_amount,
      building: building
    }

    if building do
      owner_name = Persistence.get_player_name(building[:owner_id])

      Map.merge(base, %{
        building_name: Buildings.display_name(building.type),
        building_orientation: building.orientation,
        building_status: building_status_text(building),
        building_owner_id: building[:owner_id],
        building_owner_name: owner_name
      })
    else
      Map.merge(base, %{
        building_name: nil,
        building_orientation: nil,
        building_status: nil,
        building_owner_id: nil,
        building_owner_name: nil
      })
    end
  end

  defp building_status_text(%{type: :miner, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{state.output_buffer}"
      state[:progress] > 0 -> "Mining... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  defp building_status_text(%{type: :smelter, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{state.output_buffer}"
      state[:input_buffer] != nil -> "Smelting... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  defp building_status_text(%{type: :conveyor, state: state}) do
    if state[:item], do: "Carrying: #{state.item}", else: "Empty"
  end

  defp building_status_text(_building), do: nil

  defp restore_player(params) do
    player_id =
      case params["player_id"] do
        id when is_binary(id) and id != "" -> id
        _ -> "player:#{Base.encode16(:crypto.strong_rand_bytes(8))}"
      end

    player_name =
      case params["player_name"] do
        name when is_binary(name) and name != "" -> name
        _ -> Presence.random_name()
      end

    player_color =
      case params["player_color"] do
        color when is_binary(color) and color != "" -> color
        _ -> Presence.random_color()
      end

    camera = %{
      x: to_float(params["camera_x"], 0.0),
      y: to_float(params["camera_y"], 0.0),
      z: to_float(params["camera_z"], 3.5),
      tx: to_float(params["camera_tx"], 0.0),
      ty: to_float(params["camera_ty"], 0.0),
      tz: to_float(params["camera_tz"], 0.0)
    }

    {player_id, player_name, player_color, camera}
  end

  defp to_float(val, _default) when is_float(val), do: val
  defp to_float(val, _default) when is_integer(val), do: val * 1.0
  defp to_float(nil, default), do: default
  defp to_float(_, default), do: default

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp build_buildings_snapshot do
    for face_id <- 0..29,
        {{f, r, c}, building} <- WorldStore.get_face_buildings(face_id) do
      %{
        face: f,
        row: r,
        col: c,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      }
    end
  end
end
