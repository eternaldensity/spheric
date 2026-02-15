defmodule SphericWeb.GameLive.BlueprintEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.{WorldServer, WorldStore}

  def handle_event("blueprint_capture", _params, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :capture)
      |> assign(:selected_building_type, nil)
      |> assign(:demolish_mode, false)
      |> push_event("blueprint_mode", %{mode: "capture"})
      |> push_event("demolish_mode", %{enabled: false})

    {:noreply, socket}
  end

  def handle_event("blueprint_stamp", _params, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :stamp)
      |> assign(:selected_building_type, nil)
      |> assign(:demolish_mode, false)
      |> push_event("blueprint_mode", %{mode: "stamp"})
      |> push_event("demolish_mode", %{enabled: false})

    {:noreply, socket}
  end

  def handle_event("blueprint_captured", %{"name" => _name, "count" => _count}, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :stamp)
      |> assign(:blueprint_count, socket.assigns.blueprint_count + 1)

    {:noreply, socket}
  end

  def handle_event("blueprint_cancelled", _params, socket) do
    {:noreply, assign(socket, :blueprint_mode, nil)}
  end

  def handle_event("place_blueprint", %{"buildings" => buildings_list}, socket) do
    owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

    placements =
      Enum.map(buildings_list, fn %{
                                    "face" => face,
                                    "row" => row,
                                    "col" => col,
                                    "orientation" => orientation,
                                    "type" => type_str
                                  } ->
        {{face, row, col}, String.to_existing_atom(type_str), orientation, owner}
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

        {{_face, _row, _col}, {:error, _reason}}, sock ->
          sock
      end)

    {:noreply, socket}
  end
end
