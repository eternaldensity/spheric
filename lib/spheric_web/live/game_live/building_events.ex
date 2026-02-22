defmodule SphericWeb.GameLive.BuildingEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.{WorldServer, WorldStore, Buildings}
  alias SphericWeb.GameLive.Helpers

  require Logger

  def handle_event("select_building", %{"type" => "none"}, socket) do
    socket =
      socket
      |> assign(:selected_building_type, nil)
      |> assign(:line_mode, false)
      |> assign(:blueprint_mode, nil)
      |> push_event("placement_mode", %{type: nil, orientation: nil})
      |> push_event("line_mode", %{enabled: false})
      |> push_event("blueprint_mode", %{mode: nil})

    {:noreply, socket}
  end

  def handle_event("select_building", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if Buildings.valid_type?(type) do
      orientation = socket.assigns.placement_orientation

      socket =
        socket
        |> assign(:selected_building_type, type)
        |> assign(:blueprint_mode, nil)
        |> assign(:demolish_mode, false)
        |> push_event("placement_mode", %{type: type_str, orientation: orientation})
        |> push_event("blueprint_mode", %{mode: nil})
        |> push_event("demolish_mode", %{enabled: false})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

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

  def handle_event("place_line", %{"buildings" => buildings_list}, socket) do
    case socket.assigns.selected_building_type do
      nil ->
        {:noreply, socket}

      building_type ->
        owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

        placements =
          Enum.map(buildings_list, fn %{
                                        "face" => face,
                                        "row" => row,
                                        "col" => col,
                                        "orientation" => orientation
                                      } ->
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

  def handle_event("tile_click", %{"face" => face, "row" => row, "col" => col}, socket) do
    key = {face, row, col}
    tile = %{face: face, row: row, col: col}
    Logger.debug("Tile clicked: face=#{face} row=#{row} col=#{col}")

    case socket.assigns.selected_building_type do
      nil ->
        tile_info = Helpers.build_tile_info(key)

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
            tile_info = Helpers.build_tile_info(key)

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

            socket =
              socket
              |> assign(:selected_tile, tile)
              |> assign(:tile_info, tile_info)
              |> push_event("building_placed", payload)

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

  def handle_event("remove_building", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    case WorldServer.remove_building(key, socket.assigns.player_id) do
      :ok ->
        tile_info = Helpers.build_tile_info(key)

        socket =
          socket
          |> assign(:tile_info, tile_info)
          |> push_event("building_removed", %{face: face, row: row, col: col})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("link_conduit", params, socket) do
    %{
      "face" => face,
      "row" => row,
      "col" => col,
      "target_face" => tf,
      "target_row" => tr,
      "target_col" => tc
    } = params

    key_a = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    key_b = {Helpers.to_int(tf), Helpers.to_int(tr), Helpers.to_int(tc)}

    building_a = WorldStore.get_building(key_a)
    building_b = WorldStore.get_building(key_b)

    if building_a && building_b &&
         building_a.type == :underground_conduit &&
         building_b.type == :underground_conduit &&
         building_a.owner_id == socket.assigns.player_id &&
         building_b.owner_id == socket.assigns.player_id do
      new_state_a = %{building_a.state | linked_to: key_b}
      new_state_b = %{building_b.state | linked_to: key_a}
      WorldStore.put_building(key_a, %{building_a | state: new_state_a})
      WorldStore.put_building(key_b, %{building_b | state: new_state_b})

      tile_info = Helpers.build_tile_info(key_a)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end
end
