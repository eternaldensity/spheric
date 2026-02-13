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
      |> assign(:selected_building_type, nil)
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
      data-geometry={Jason.encode!(@geometry_data)}
      data-terrain={Jason.encode!(@terrain_data)}
      style="width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0;"
    >
    </div>

    <div
      :if={@selected_tile}
      style="position: fixed; top: 16px; left: 16px; background: rgba(0,0,0,0.7); color: #fff; padding: 8px 14px; border-radius: 6px; font-family: monospace; font-size: 14px; pointer-events: none;"
    >
      Face {@selected_tile.face} &middot; Row {@selected_tile.row} &middot; Col {@selected_tile.col}
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
      <button
        :if={@selected_building_type}
        phx-click="select_building"
        phx-value-type="none"
        style="padding: 8px 16px; border: 2px solid #888; border-radius: 6px; background: rgba(255,255,255,0.1); color: #aaa; cursor: pointer; font-family: monospace; font-size: 13px;"
      >
        Cancel
      </button>
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
  def handle_event("tile_click", %{"face" => face, "row" => row, "col" => col}, socket) do
    tile = %{face: face, row: row, col: col}
    Logger.debug("Tile clicked: face=#{face} row=#{row} col=#{col}")

    case socket.assigns.selected_building_type do
      nil ->
        {:noreply, assign(socket, :selected_tile, tile)}

      building_type ->
        key = {face, row, col}

        case WorldServer.place_building(key, building_type) do
          :ok ->
            building = WorldStore.get_building(key)

            socket =
              socket
              |> assign(:selected_tile, tile)
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
    key = {face, row, col}

    case WorldServer.remove_building(key) do
      :ok ->
        socket =
          socket
          |> push_event("building_removed", %{face: face, row: row, col: col})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
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
