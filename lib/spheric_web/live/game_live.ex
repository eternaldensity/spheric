defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Geometry.Coordinate

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()

    socket =
      socket
      |> assign(:page_title, "Spheric")
      |> assign(:geometry_data, geometry_data)
      |> assign(:selected_tile, nil)
      |> assign(:camera_pos, {0.0, 0.0, 3.5})
      |> assign(:visible_faces, MapSet.new(0..29))

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
      style="width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0;"
    >
    </div>

    <div
      :if={@selected_tile}
      style="position: fixed; top: 16px; left: 16px; background: rgba(0,0,0,0.7); color: #fff; padding: 8px 14px; border-radius: 6px; font-family: monospace; font-size: 14px; pointer-events: none;"
    >
      Face {@selected_tile.face} &middot; Row {@selected_tile.row} &middot; Col {@selected_tile.col}
    </div>
    """
  end

  @impl true
  def handle_event("tile_click", %{"face" => face, "row" => row, "col" => col}, socket) do
    tile = %{face: face, row: row, col: col}
    Logger.debug("Tile clicked: face=#{face} row=#{row} col=#{col}")
    {:noreply, assign(socket, :selected_tile, tile)}
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
end
