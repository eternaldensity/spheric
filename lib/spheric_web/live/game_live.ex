defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Geometry.Coordinate
  alias Spheric.Game.{WorldServer, WorldStore, Buildings}

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()
    subdivisions = Application.get_env(:spheric, :subdivisions, 16)

    # Build terrain payload: per-face list of {terrain, resource_type} for each tile
    terrain_data = build_terrain_data(subdivisions)

    # Build initial buildings snapshot
    buildings_data = build_buildings_snapshot()

    # Subscribe to all face PubSub topics
    if connected?(socket) do
      for face_id <- 0..29 do
        Phoenix.PubSub.subscribe(Spheric.PubSub, "world:face:#{face_id}")
      end
    end

    socket =
      socket
      |> assign(:page_title, "Spheric")
      |> assign(:geometry_data, geometry_data)
      |> assign(:terrain_data, terrain_data)
      |> assign(:selected_tile, nil)
      |> assign(:tile_info, nil)
      |> assign(:selected_building_type, nil)
      |> assign(:placement_orientation, 0)
      |> assign(:camera_pos, {0.0, 0.0, 3.5})
      |> assign(:visible_faces, MapSet.new(0..29))
      |> assign(:building_types, Buildings.types())
      |> push_event("buildings_snapshot", %{buildings: buildings_data})

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
      data-terrain={Jason.encode!(@terrain_data)}
      style="width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0;"
    >
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
      <div :if={@tile_info.building} style="margin-top: 4px; border-top: 1px solid #444; padding-top: 4px;">
        <div>
          Building: <span style="color: #fd4">{@tile_info.building_name}</span>
        </div>
        <div style="color: #aaa; font-size: 11px;">
          Orientation: {@tile_info.building_orientation}
          ({direction_label(@tile_info.building_orientation)})
        </div>
        <div :if={@tile_info.building_status} style="color: #aaa; font-size: 11px;">
          {@tile_info.building_status}
        </div>
        <button
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
      <div :if={@selected_building_type} style="display: flex; align-items: center; gap: 4px; margin-left: 8px; padding-left: 8px; border-left: 1px solid #555;">
        <button
          phx-click="rotate_building"
          style="padding: 8px 12px; border: 2px solid #77aaff; border-radius: 6px; background: rgba(119,170,255,0.15); color: #aaddff; cursor: pointer; font-family: monospace; font-size: 13px;"
          title="Rotate (R key)"
        >
          {direction_label(@placement_orientation)}
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
    {:noreply, assign(socket, :selected_building_type, nil)}
  end

  @impl true
  def handle_event("select_building", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if Buildings.valid_type?(type) do
      {:noreply, assign(socket, :selected_building_type, type)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rotate_building", _params, socket) do
    new_orientation = rem(socket.assigns.placement_orientation + 1, 4)
    {:noreply, assign(socket, :placement_orientation, new_orientation)}
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

        case WorldServer.place_building(key, building_type, orientation) do
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

    case WorldServer.remove_building(key) do
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
      new_orientation = rem(socket.assigns.placement_orientation + 1, 4)
      {:noreply, assign(socket, :placement_orientation, new_orientation)}
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

    socket =
      socket
      |> assign(:camera_pos, camera_pos)
      |> assign(:visible_faces, visible)

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

  # --- Helpers ---

  defp build_terrain_data(subdivisions) do
    for face_id <- 0..29 do
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
  end

  defp direction_label(0), do: "Right"
  defp direction_label(1), do: "Down"
  defp direction_label(2), do: "Left"
  defp direction_label(3), do: "Up"

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
      Map.merge(base, %{
        building_name: Buildings.display_name(building.type),
        building_orientation: building.orientation,
        building_status: building_status_text(building)
      })
    else
      Map.merge(base, %{
        building_name: nil,
        building_orientation: nil,
        building_status: nil
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
