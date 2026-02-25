defmodule SphericWeb.GameLive.BuildingEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.{WorldServer, WorldStore, Buildings, StarterKit, GroundItems, Research}
  alias Spheric.Game.Behaviors.DroneBay
  alias Spheric.Game.Persistence
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

    # Intercept for linking modes
    cond do
      match?({mode, _} when mode in [:source, :destination], socket.assigns[:arm_linking]) ->
        {mode, arm_key} = socket.assigns.arm_linking
        handle_arm_link(socket, arm_key, key, mode)

      socket.assigns[:conduit_linking] != nil ->
        handle_conduit_link(socket, socket.assigns.conduit_linking, key)

      true ->
        handle_normal_tile_click(socket, key, tile, face, row, col)
    end
  end

  defp handle_arm_link(socket, arm_key, target_key, mode) do
    building = WorldStore.get_building(arm_key)

    valid =
      building != nil and
        building.type in [:loader, :unloader] and
        building.owner_id == socket.assigns.player_id and
        arm_within_range?(arm_key, target_key) and
        validate_arm_target(building.type, mode, target_key)

    if valid do
      new_state =
        case mode do
          :source -> %{building.state | source: target_key}
          :destination -> %{building.state | destination: target_key}
        end

      WorldStore.put_building(arm_key, %{building | state: new_state})
      tile_info = Helpers.build_tile_info(arm_key)

      socket =
        socket
        |> assign(:arm_linking, nil)
        |> assign(:tile_info, tile_info)
        |> assign(:selected_tile, %{
          face: elem(arm_key, 0),
          row: elem(arm_key, 1),
          col: elem(arm_key, 2)
        })

      {:noreply, socket}
    else
      {:noreply, assign(socket, :arm_linking, nil)}
    end
  end

  defp handle_conduit_link(socket, conduit_key, target_key) do
    building_a = WorldStore.get_building(conduit_key)
    building_b = WorldStore.get_building(target_key)

    valid =
      conduit_key != target_key and
        building_a != nil and building_b != nil and
        building_a.type == :underground_conduit and
        building_b.type == :underground_conduit and
        (building_a.owner_id == nil or building_a.owner_id == socket.assigns.player_id) and
        (building_b.owner_id == nil or building_b.owner_id == socket.assigns.player_id)

    if valid do
      # Unlink any previous partners
      for {_bldg, partner_key} <- [{building_a, building_a.state[:linked_to]}, {building_b, building_b.state[:linked_to]}],
          partner_key != nil,
          partner_key != conduit_key,
          partner_key != target_key do
        old_partner = WorldStore.get_building(partner_key)

        if old_partner && old_partner.type == :underground_conduit do
          WorldStore.put_building(partner_key, %{old_partner | state: %{old_partner.state | linked_to: nil}})
        end
      end

      # Link the pair
      WorldStore.put_building(conduit_key, %{building_a | state: %{building_a.state | linked_to: target_key}})
      WorldStore.put_building(target_key, %{building_b | state: %{building_b.state | linked_to: conduit_key}})

      tile_info = Helpers.build_tile_info(conduit_key)

      socket =
        socket
        |> assign(:conduit_linking, nil)
        |> assign(:tile_info, tile_info)
        |> assign(:selected_tile, %{
          face: elem(conduit_key, 0),
          row: elem(conduit_key, 1),
          col: elem(conduit_key, 2)
        })

      {:noreply, socket}
    else
      {:noreply, assign(socket, :conduit_linking, nil)}
    end
  end

  defp arm_within_range?({f1, r1, c1}, {f2, r2, c2}) do
    f1 == f2 and abs(r1 - r2) + abs(c1 - c2) <= 2
  end

  defp validate_arm_target(:unloader, :source, _target_key), do: true

  defp validate_arm_target(:unloader, :destination, target_key) do
    case WorldStore.get_building(target_key) do
      %{type: :storage_container} -> true
      _ -> false
    end
  end

  defp validate_arm_target(:loader, :source, target_key) do
    case WorldStore.get_building(target_key) do
      %{type: :storage_container} -> true
      _ -> false
    end
  end

  defp validate_arm_target(:loader, :destination, _target_key), do: true

  defp handle_normal_tile_click(socket, key, tile, face, row, col) do
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
              |> assign(:starter_kit_remaining, StarterKit.get_remaining(socket.assigns.player_id))
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
          |> assign(:starter_kit_remaining, StarterKit.get_remaining(socket.assigns.player_id))
          |> push_event("building_removed", %{face: face, row: row, col: col})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("eject_output", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    case WorldServer.eject_output(key, socket.assigns.player_id) do
      {:ok, _item} ->
        tile_info = Helpers.build_tile_info(key)
        {:noreply, assign(socket, :tile_info, tile_info)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("flush_inputs", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    case WorldServer.flush_inputs(key, socket.assigns.player_id) do
      {:ok, _items} ->
        tile_info = Helpers.build_tile_info(key)
        {:noreply, assign(socket, :tile_info, tile_info)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("rotate_placed_building", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    case WorldServer.rotate_building(key, socket.assigns.player_id) do
      :ok ->
        building = WorldStore.get_building(key)
        tile_info = Helpers.build_tile_info(key)

        socket =
          socket
          |> assign(:tile_info, tile_info)
          |> push_event("building_rotated", %{
            face: face,
            row: row,
            col: col,
            type: Atom.to_string(building.type),
            orientation: building.orientation
          })

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_power", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    case WorldServer.toggle_power(key, socket.assigns.player_id) do
      :ok ->
        tile_info = Helpers.build_tile_info(key)
        {:noreply, assign(socket, :tile_info, tile_info)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # Conduit linking: enter linking mode so next tile_click pairs two underground conduits
  def handle_event(
        "start_conduit_link",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :underground_conduit &&
         (building.owner_id == nil or building.owner_id == socket.assigns.player_id) do
      {:noreply, assign(socket, :conduit_linking, key)}
    else
      {:noreply, socket}
    end
  end

  # Conduit unlink: clear linked_to on both paired conduits
  def handle_event(
        "unlink_conduit",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :underground_conduit &&
         (building.owner_id == nil or building.owner_id == socket.assigns.player_id) &&
         building.state[:linked_to] != nil do
      # Unlink the partner too
      partner_key = building.state.linked_to
      partner = WorldStore.get_building(partner_key)

      if partner && partner.type == :underground_conduit do
        WorldStore.put_building(partner_key, %{partner | state: %{partner.state | linked_to: nil}})
      end

      WorldStore.put_building(key, %{building | state: %{building.state | linked_to: nil}})
      tile_info = Helpers.build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  # Arm linking: enter linking mode so next tile_click assigns source or destination
  def handle_event(
        "start_arm_link",
        %{"face" => face, "row" => row, "col" => col, "mode" => mode},
        socket
      ) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    arm_key = {face, row, col}

    building = WorldStore.get_building(arm_key)

    if building && building.type in [:loader, :unloader] &&
         building.owner_id == socket.assigns.player_id do
      link_mode = String.to_existing_atom(mode)
      {:noreply, assign(socket, :arm_linking, {link_mode, arm_key})}
    else
      {:noreply, socket}
    end
  end

  # Arm upgrade: toggle bulk transfer
  def handle_event(
        "upgrade_arm",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    building = WorldStore.get_building(key)

    if building && building.type in [:loader, :unloader] &&
         building.owner_id == socket.assigns.player_id do
      new_state = %{building.state | stack_upgrade: !building.state[:stack_upgrade]}
      WorldStore.put_building(key, %{building | state: new_state})
      tile_info = Helpers.build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  # Drone fuel pickup: client requests fuel from a ground tile
  def handle_event("pickup_fuel", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    ground = GroundItems.get(key)

    result =
      cond do
        Map.get(ground, :biofuel, 0) > 0 ->
          GroundItems.take(key, :biofuel)
          {:ok, :biofuel}

        Map.get(ground, :refined_fuel, 0) > 0 ->
          GroundItems.take(key, :refined_fuel)
          {:ok, :refined_fuel}

        true ->
          :empty
      end

    case result do
      {:ok, fuel_type} ->
        {:noreply,
         push_event(socket, "fuel_pickup_result", %{
           success: true,
           item: Atom.to_string(fuel_type)
         })}

      :empty ->
        {:noreply, push_event(socket, "fuel_pickup_result", %{success: false})}
    end
  end

  # Drone cargo: pick up a ground item or belt item into drone cargo.
  # Checks ground items first (exact tile then radius-1 neighbors),
  # then tries to grab from a conveyor on the tile.
  def handle_event("drone_pickup_item", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    # Try belt item first (exact tile), then ground items (exact + radius-1)
    result =
      try_belt_pickup(key) ||
        case Map.to_list(GroundItems.get(key)) do
          [{item_type, _count} | _] ->
            {:ground, key, item_type}

          [] ->
            GroundItems.items_near(key, 1)
            |> Enum.find_value(nil, fn {tile_key, items} ->
              case Map.to_list(items) do
                [{item_type, _count} | _] -> {:ground, tile_key, item_type}
                [] -> nil
              end
            end)
        end

    case result do
      {:ground, pickup_key, item_type} ->
        GroundItems.take(pickup_key, item_type)

        {:noreply,
         push_event(socket, "item_pickup_result", %{
           success: true,
           item: Atom.to_string(item_type)
         })}

      {:belt, belt_key, item_type} ->
        take_belt_item(belt_key, item_type)

        {:noreply,
         push_event(socket, "item_pickup_result", %{
           success: true,
           item: Atom.to_string(item_type)
         })}

      nil ->
        {:noreply, push_event(socket, "item_pickup_result", %{success: false})}
    end
  end

  # Drone cargo: drop a held item onto a tile.
  # Prefers placing onto an empty conveyor slot; falls back to ground.
  def handle_event(
        "drone_drop_item",
        %{"face" => face, "row" => row, "col" => col, "item" => item_str},
        socket
      ) do
    face = Helpers.to_int(face)
    row = Helpers.to_int(row)
    col = Helpers.to_int(col)
    key = {face, row, col}

    item =
      try do
        String.to_existing_atom(item_str)
      rescue
        ArgumentError -> nil
      end

    if item do
      building = WorldStore.get_building(key)

      if building && belt_type?(building.type) && building.state[:item] == nil do
        new_state = %{building.state | item: item}
        WorldStore.put_building(key, %{building | state: new_state})
      else
        GroundItems.add(key, item)
      end

      {:noreply, push_event(socket, "item_drop_result", %{success: true})}
    else
      {:noreply, push_event(socket, "item_drop_result", %{success: false})}
    end
  end

  @belt_types [:conveyor, :conveyor_mk2, :conveyor_mk3, :crossover]

  defp belt_type?(type), do: type in @belt_types

  defp try_belt_pickup(key) do
    building = WorldStore.get_building(key)

    if building && belt_type?(building.type) && building.state[:item] != nil do
      {:belt, key, building.state.item}
    else
      nil
    end
  end

  defp take_belt_item(key, _item_type) do
    building = WorldStore.get_building(key)

    if building do
      new_state = %{building.state | item: nil}
      WorldStore.put_building(key, %{building | state: new_state})
    end
  end

  # Drone bay: player claims a completed upgrade (recovery for stuck :complete state)
  def handle_event(
        "claim_drone_upgrade",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :drone_bay &&
         building.state[:mode] == :complete &&
         building.state[:selected_upgrade] != nil &&
         building.owner_id == socket.assigns.player_id do
      upgrade = building.state.selected_upgrade

      # Persist the upgrade to DB
      Persistence.apply_drone_upgrade(socket.assigns.player_id, upgrade)

      # Apply upgrade-specific effects on the building
      new_state = DroneBay.cancel_upgrade(building.state)

      new_state =
        case upgrade do
          :auto_refuel -> %{new_state | auto_refuel_enabled: true}
          :delivery_drone -> %{new_state | delivery_drone_enabled: true}
          :delivery_cargo -> %{new_state | delivery_cargo_capacity: 4}
          _ -> new_state
        end

      WorldStore.put_building(key, %{building | state: new_state})

      # Notify client of the granted upgrade
      socket =
        socket
        |> assign(:tile_info, Helpers.build_tile_info(key))
        |> push_event("drone_upgrade_granted", %{upgrade: Atom.to_string(upgrade)})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Drone bay: player selects an upgrade to install
  def handle_event(
        "select_drone_upgrade",
        %{"face" => face, "row" => row, "col" => col, "upgrade" => upgrade_str},
        socket
      ) do
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}

    upgrade =
      try do
        String.to_existing_atom(upgrade_str)
      rescue
        ArgumentError -> nil
      end

    building = WorldStore.get_building(key)

    if upgrade && building && building.type == :drone_bay &&
         building.owner_id == socket.assigns.player_id do
      player_upgrades = Persistence.get_drone_upgrades(socket.assigns.player_id)
      clearance_level = Research.clearance_level(socket.assigns.player_id)
      new_state = DroneBay.select_upgrade(building.state, upgrade, player_upgrades, clearance_level)
      WorldStore.put_building(key, %{building | state: new_state})
      tile_info = Helpers.build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  # Drone bay: player cancels upgrade selection
  def handle_event(
        "cancel_drone_upgrade",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :drone_bay &&
         building.owner_id == socket.assigns.player_id do
      new_state = DroneBay.cancel_upgrade(building.state)
      WorldStore.put_building(key, %{building | state: new_state})
      tile_info = Helpers.build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  # Object of Power: Pneumatic Transit Network — teleport between owned terminals
  def handle_event(
        "teleport_to_terminal",
        %{"face" => face, "row" => row, "col" => col},
        socket
      ) do
    player_id = socket.assigns.player_id

    if Spheric.Game.ObjectsOfPower.player_has?(player_id, :terminal_network) do
      dest = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
      building = WorldStore.get_building(dest)

      if building && building.type == :submission_terminal &&
           building.owner_id == player_id do
        {f, r, c} = dest
        socket = push_event(socket, "teleport_to_terminal", %{face: f, row: r, col: c})
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # List all owned terminals for teleportation menu
  def handle_event("list_terminals", _params, socket) do
    player_id = socket.assigns.player_id

    if Spheric.Game.ObjectsOfPower.player_has?(player_id, :terminal_network) do
      terminals =
        for face_id <- 0..29,
            {key, building} <- WorldStore.get_face_buildings(face_id),
            building.type == :submission_terminal,
            building.owner_id == player_id do
          {f, r, c} = key
          %{face: f, row: r, col: c}
        end

      socket = push_event(socket, "terminal_list", %{terminals: terminals})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

end
