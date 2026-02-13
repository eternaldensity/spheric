defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()

    socket =
      socket
      |> assign(:page_title, "Spheric")
      |> assign(:geometry_data, geometry_data)

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
    """
  end
end
