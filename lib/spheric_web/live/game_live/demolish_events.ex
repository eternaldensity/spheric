defmodule SphericWeb.GameLive.DemolishEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.WorldServer
  alias SphericWeb.GameLive.Helpers

  def handle_event("toggle_demolish_mode", _params, socket) do
    new_mode = !socket.assigns.demolish_mode

    socket =
      socket
      |> assign(:demolish_mode, new_mode)
      |> assign(:selected_building_type, nil)
      |> assign(:line_mode, false)
      |> assign(:blueprint_mode, nil)
      |> push_event("demolish_mode", %{enabled: new_mode})
      |> push_event("placement_mode", %{type: nil, orientation: nil})
      |> push_event("line_mode", %{enabled: false})
      |> push_event("blueprint_mode", %{mode: nil})

    {:noreply, socket}
  end

  def handle_event("remove_area", %{"tiles" => tiles_list}, socket) do
    keys =
      Enum.map(tiles_list, fn %{"face" => face, "row" => row, "col" => col} ->
        {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
      end)

    results = WorldServer.remove_buildings(keys, socket.assigns.player_id)

    socket =
      Enum.reduce(results, socket, fn
        {{face, row, col}, :ok}, sock ->
          push_event(sock, "building_removed", %{face: face, row: row, col: col})

        {{face, row, col}, {:error, _reason}}, sock ->
          push_event(sock, "remove_error", %{face: face, row: row, col: col})
      end)

    {:noreply, socket}
  end
end
