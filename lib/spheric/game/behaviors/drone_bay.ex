defmodule Spheric.Game.Behaviors.DroneBay do
  @moduledoc """
  Drone Bay building behavior.

  A personal upgrade station for the player's camera drone.
  Operates as a state machine:
    - :idle — no upgrade selected, does not accept conveyor input
    - :accepting — an upgrade is selected, accepts specific items toward its cost
    - :complete — all items delivered, upgrade ready to apply

  When the auto_refuel upgrade is purchased, the bay also accepts
  biofuel/refined_fuel into a small internal buffer for auto-refuelling
  the drone when it flies nearby.

  The delivery_drone upgrade adds an automated delivery drone that flies
  between storage vaults and construction sites to deliver materials.
  """

  alias Spheric.Game.{ConstructionCosts, GroundItems}

  @fuel_buffer_max 5
  @delivery_fuel_tank_max 3
  @tick_seconds 0.2

  @upgrade_costs %{
    auto_refuel: %{iron_ingot: 5, copper_ingot: 3, wire: 2},
    expanded_tank: %{plate: 3, circuit: 2, wire: 4},
    drone_spotlight: %{iron_ingot: 4, wire: 3, copper_ingot: 2},
    expanded_cargo: %{plate: 5, circuit: 3, wire: 6},
    delivery_drone: %{frame: 3, circuit: 3, motor: 2, biofuel: 5},
    delivery_cargo: %{heavy_frame: 2, advanced_circuit: 1, motor: 2},
    upgrade_delivery: %{heavy_frame: 3, advanced_circuit: 2, motor: 1, cable: 4}
  }

  @upgrade_clearance %{
    delivery_drone: 3,
    delivery_cargo: 4,
    upgrade_delivery: 4
  }

  @fuel_durations %{
    biofuel: 60.0,
    catalysed_fuel: 90.0,
    refined_fuel: 150.0,
    unstable_fuel: 30.0,
    stable_fuel: 480.0
  }

  def initial_state do
    %{
      mode: :idle,
      selected_upgrade: nil,
      required: %{},
      delivered: %{},
      fuel_buffer: [],
      auto_refuel_enabled: false,
      powered: true,
      # Delivery drone state
      delivery_drone_enabled: false,
      upgrade_delivery_enabled: false,
      delivery_state: :idle,
      delivery_fuel: nil,
      delivery_fuel_tank: [],
      delivery_cargo: [],
      delivery_cargo_capacity: 2,
      delivery_pos: nil,
      delivery_target: nil,
      delivery_path: [],
      delivery_storage_target: nil,
      delivery_site_target: nil,
      delivery_items_needed: []
    }
  end

  @doc "Returns the list of available upgrade atoms."
  def upgrades, do: Map.keys(@upgrade_costs)

  @doc "Returns the resource cost map for a given upgrade."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})

  @doc "Returns all upgrade costs (for UI display)."
  def all_upgrade_costs, do: @upgrade_costs

  @doc "Returns the clearance level required for an upgrade (0 if none)."
  def upgrade_clearance(upgrade), do: Map.get(@upgrade_clearance, upgrade, 0)

  @doc "Max fuel buffer size for auto-refuel."
  def fuel_buffer_max, do: @fuel_buffer_max

  @doc "Drone bay is passive — no autonomous production."
  def tick(_key, building), do: building

  @doc """
  Select an upgrade to install. Puts the bay into :accepting mode.
  Returns the updated state, or the original state if the upgrade
  is invalid or already purchased, or if the player lacks clearance.
  """
  def select_upgrade(state, upgrade, player_upgrades, clearance_level \\ 0) do
    required_clearance = Map.get(@upgrade_clearance, upgrade, 0)

    if upgrade in upgrades() and
         not Map.get(player_upgrades, Atom.to_string(upgrade), false) and
         clearance_level >= required_clearance do
      cost = upgrade_cost(upgrade)

      %{
        state
        | mode: :accepting,
          selected_upgrade: upgrade,
          required: cost,
          delivered: Map.new(cost, fn {k, _v} -> {k, 0} end)
      }
    else
      state
    end
  end

  @doc "Cancel the current upgrade selection. Returns to idle mode."
  def cancel_upgrade(state) do
    %{state | mode: :idle, selected_upgrade: nil, required: %{}, delivered: %{}}
  end

  @doc """
  Try to accept an item into the drone bay.
  Returns the updated state if accepted, or nil if rejected.
  """
  def try_accept_item(%{mode: :accepting, required: req, delivered: del} = state, item) do
    needed = Map.get(req, item, 0)
    have = Map.get(del, item, 0)

    if have < needed do
      new_del = Map.put(del, item, have + 1)
      new_state = %{state | delivered: new_del}

      if upgrade_complete?(new_state) do
        %{new_state | mode: :complete}
      else
        new_state
      end
    else
      nil
    end
  end

  def try_accept_item(
        %{mode: :idle, fuel_buffer: buf, auto_refuel_enabled: true} = state,
        item
      )
      when item in [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel] and length(buf) < @fuel_buffer_max do
    %{state | fuel_buffer: buf ++ [item]}
  end

  def try_accept_item(_state, _item), do: nil

  @doc "Returns true when the bay cannot accept any more input."
  def full?(%{mode: :accepting, required: req, delivered: del}) do
    Enum.all?(req, fn {item, needed} -> Map.get(del, item, 0) >= needed end)
  end

  def full?(%{mode: :idle, auto_refuel_enabled: true, fuel_buffer: buf}) do
    length(buf) >= @fuel_buffer_max
  end

  def full?(_state), do: true

  # ── Delivery Drone Logic ────────────────────────────────────────────────

  @doc """
  Process one tick of delivery drone behavior. Returns {updated_buildings, drone_update_or_nil}.
  The drone_update is a map for broadcasting to clients, or nil if drone is idle/docked.
  """
  def process_delivery_tick(bay_key, bay_building, buildings) do
    state = bay_building.state

    unless state[:delivery_drone_enabled] == true and state[:powered] != false do
      {buildings, nil}
    else
      # Step 1: Burn fuel if flying
      state = burn_delivery_fuel(state)

      # Step 2: Refuel from bay's fuel buffer if possible
      state = refuel_delivery_drone(state)

      # Step 3: Handle state machine
      {state, buildings} = delivery_state_machine(bay_key, state, buildings, bay_building[:owner_id])

      # Update the bay building in the buildings map
      buildings = Map.put(buildings, bay_key, %{bay_building | state: state})

      # Build broadcast update if drone is active (not idle at bay)
      update =
        if state.delivery_state != :idle do
          %{
            bay_key: bay_key,
            pos: state.delivery_pos || bay_key,
            state: state.delivery_state,
            cargo: state.delivery_cargo
          }
        else
          nil
        end

      {buildings, update}
    end
  end

  @doc "Check if two tile keys are within delivery range. Base is adjacent cells (±1). Area creature boost extends range."
  def delivery_in_range?(bay_key, target_key, owner_id \\ nil)

  def delivery_in_range?({f1, r1, c1} = bay_key, {f2, r2, c2}, owner_id) do
    area = Spheric.Game.Creatures.area_value(bay_key, owner_id)
    max_cells = round(1 * (1.0 + area))

    f1 == f2 and
      abs(div(r1, 16) - div(r2, 16)) <= max_cells and
      abs(div(c1, 16) - div(c2, 16)) <= max_cells
  end

  @doc "Compute a Manhattan path from src to dest (row first, then col). Returns list of tiles excluding src."
  def compute_path({f, r1, c1}, {f, r2, c2}) do
    row_tiles =
      if r2 == r1 do
        []
      else
        dir = if r2 > r1, do: 1, else: -1
        for r <- (r1 + dir)..r2//dir, do: {f, r, c1}
      end

    col_tiles =
      if c2 == c1 do
        []
      else
        dir = if c2 > c1, do: 1, else: -1
        for c <- (c1 + dir)..c2//dir, do: {f, r2, c}
      end

    row_tiles ++ col_tiles
  end

  def compute_path(_src, _dst), do: []

  # ── Private Delivery Helpers ────────────────────────────────────────────

  defp burn_delivery_fuel(%{delivery_state: :idle} = state), do: state

  defp burn_delivery_fuel(state) do
    case state.delivery_fuel do
      {fuel_type, remaining} ->
        new_remaining = remaining - @tick_seconds

        if new_remaining <= 0 do
          # Current fuel depleted, try to use next from tank
          case state.delivery_fuel_tank do
            [next | rest] ->
              duration = Map.get(@fuel_durations, next, 60.0)
              %{state | delivery_fuel: {next, duration}, delivery_fuel_tank: rest}

            [] ->
              # Out of fuel — drop cargo and return to idle
              drop_cargo_and_idle(state)
          end
        else
          %{state | delivery_fuel: {fuel_type, new_remaining}}
        end

      nil ->
        # No fuel at all — try from tank
        case state.delivery_fuel_tank do
          [next | rest] ->
            duration = Map.get(@fuel_durations, next, 60.0)
            %{state | delivery_fuel: {next, duration}, delivery_fuel_tank: rest}

          [] ->
            # No fuel available
            if state.delivery_state != :idle do
              drop_cargo_and_idle(state)
            else
              state
            end
        end
    end
  end

  defp drop_cargo_and_idle(state) do
    # Drop cargo as ground items at current position
    pos = state.delivery_pos

    if pos && state.delivery_cargo != [] do
      for item <- state.delivery_cargo do
        GroundItems.add(pos, item)
      end
    end

    %{
      state
      | delivery_state: :idle,
        delivery_fuel: nil,
        delivery_cargo: [],
        delivery_pos: nil,
        delivery_target: nil,
        delivery_path: [],
        delivery_storage_target: nil,
        delivery_site_target: nil,
        delivery_items_needed: []
    }
  end

  defp refuel_delivery_drone(state) do
    tank = state[:delivery_fuel_tank] || []
    fuel_buffer = state[:fuel_buffer] || []

    if length(tank) < @delivery_fuel_tank_max and
         state[:auto_refuel_enabled] == true and
         fuel_buffer != [] do
      [fuel_item | rest_buffer] = fuel_buffer
      %{state | delivery_fuel_tank: tank ++ [fuel_item], fuel_buffer: rest_buffer}
    else
      state
    end
  end

  defp delivery_state_machine(bay_key, %{delivery_state: :idle} = state, buildings, owner_id) do
    # Check if we have fuel
    has_fuel = state.delivery_fuel != nil or state.delivery_fuel_tank != []

    if has_fuel do
      # Ensure we have active fuel loaded
      state =
        if state.delivery_fuel == nil do
          case state.delivery_fuel_tank do
            [next | rest] ->
              duration = Map.get(@fuel_durations, next, 60.0)
              %{state | delivery_fuel: {next, duration}, delivery_fuel_tank: rest}

            [] ->
              state
          end
        else
          state
        end

      if state.delivery_fuel == nil do
        {state, buildings}
      else
        # Find a construction site in range that needs materials
        case find_delivery_task(bay_key, buildings, owner_id, state[:upgrade_delivery_enabled] == true) do
          nil ->
            {state, buildings}

          {site_key, storage_key, items_needed} ->
            path = compute_path(bay_key, storage_key)

            state = %{
              state
              | delivery_state: :flying_to_storage,
                delivery_pos: bay_key,
                delivery_target: storage_key,
                delivery_path: path,
                delivery_storage_target: storage_key,
                delivery_site_target: site_key,
                delivery_items_needed: items_needed
            }

            # Move one step immediately
            {state, _} = move_one_step(state)
            {state, buildings}
        end
      end
    else
      {state, buildings}
    end
  end

  defp delivery_state_machine(bay_key, %{delivery_state: :flying_to_storage} = state, buildings, _owner_id) do
    case state.delivery_path do
      [] ->
        # Arrived at storage — extract items
        storage_key = state.delivery_storage_target
        capacity = state[:delivery_cargo_capacity] || 2
        items_needed = state.delivery_items_needed

        {cargo, buildings} = extract_from_storage(storage_key, items_needed, capacity, buildings)

        if cargo == [] do
          # Storage empty or gone — return to bay
          path = compute_path(state.delivery_pos, bay_key)

          state = %{
            state
            | delivery_state: :returning,
              delivery_target: bay_key,
              delivery_path: path,
              delivery_cargo: [],
              delivery_storage_target: nil,
              delivery_site_target: nil,
              delivery_items_needed: []
          }

          {state, _} = move_one_step(state)
          {state, buildings}
        else
          # Compute path to construction site
          site_key = state.delivery_site_target
          path = compute_path(state.delivery_pos, site_key)

          state = %{
            state
            | delivery_state: :flying_to_site,
              delivery_target: site_key,
              delivery_path: path,
              delivery_cargo: cargo
          }

          {state, _} = move_one_step(state)
          {state, buildings}
        end

      _path ->
        {state, _} = move_one_step(state)
        {state, buildings}
    end
  end

  defp delivery_state_machine(bay_key, %{delivery_state: :flying_to_site} = state, buildings, _owner_id) do
    case state.delivery_path do
      [] ->
        # Arrived at construction site — deliver items
        site_key = state.delivery_site_target
        buildings = deliver_to_site(site_key, state.delivery_cargo, buildings)

        # Return to bay
        path = compute_path(state.delivery_pos, bay_key)

        state = %{
          state
          | delivery_state: :returning,
            delivery_target: bay_key,
            delivery_path: path,
            delivery_cargo: [],
            delivery_storage_target: nil,
            delivery_site_target: nil,
            delivery_items_needed: []
        }

        {state, _} = move_one_step(state)
        {state, buildings}

      _path ->
        {state, _} = move_one_step(state)
        {state, buildings}
    end
  end

  defp delivery_state_machine(_bay_key, %{delivery_state: :returning} = state, buildings, _owner_id) do
    case state.delivery_path do
      [] ->
        # Arrived back at bay — go idle
        state = %{
          state
          | delivery_state: :idle,
            delivery_pos: nil,
            delivery_target: nil,
            delivery_path: [],
            delivery_storage_target: nil,
            delivery_site_target: nil,
            delivery_items_needed: []
        }

        {state, buildings}

      _path ->
        {state, _} = move_one_step(state)
        {state, buildings}
    end
  end

  defp delivery_state_machine(_bay_key, state, buildings, _owner_id), do: {state, buildings}

  defp move_one_step(%{delivery_path: []} = state), do: {state, false}

  defp move_one_step(%{delivery_path: [next | rest]} = state) do
    {%{state | delivery_pos: next, delivery_path: rest}, true}
  end

  @upgradeable_types [:loader, :unloader, :filtered_splitter, :overflow_gate, :priority_merger]

  defp find_delivery_task(bay_key, buildings, owner_id, upgrade_delivery_enabled) do
    # Find construction sites and (optionally) buildings with pending upgrades in range
    sites =
      Enum.filter(buildings, fn {key, b} ->
        in_range = delivery_in_range?(bay_key, key, owner_id)

        construction_site =
          b.state[:construction] != nil and
            b.state.construction.complete == false

        upgrade_site =
          upgrade_delivery_enabled and
            b.type in @upgradeable_types and
            b.state[:upgrade_progress] != nil and
            b.state.upgrade_progress.complete == false

        in_range and (construction_site or upgrade_site)
      end)

    # For each site, check what items are needed and if any storage has them
    Enum.find_value(sites, fn {site_key, site} ->
      progress =
        if site.state[:construction] != nil and site.state.construction.complete == false do
          site.state.construction
        else
          site.state[:upgrade_progress]
        end

      needed_items =
        Enum.flat_map(progress.required, fn {item, qty} ->
          delivered = Map.get(progress.delivered, item, 0)
          if delivered < qty, do: [item], else: []
        end)

      if needed_items == [] do
        nil
      else
        # Find a storage container in range with any of the needed items
        storage =
          Enum.find(buildings, fn {key, b} ->
            b.type == :storage_container and
              delivery_in_range?(bay_key, key, owner_id) and
              b.state[:item_type] in needed_items and
              b.state[:count] > 0
          end)

        case storage do
          {storage_key, _storage_building} ->
            {site_key, storage_key, needed_items}

          nil ->
            nil
        end
      end
    end)
  end

  defp extract_from_storage(storage_key, items_needed, capacity, buildings) do
    case Map.get(buildings, storage_key) do
      %{type: :storage_container, state: %{item_type: item_type, count: count} = st} = b
      when not is_nil(item_type) and count > 0 ->
        if item_type in items_needed do
          # Extract up to capacity items
          take = min(count, capacity)
          new_count = count - take
          inserted = st[:inserted_count] || 0
          new_type = if new_count == 0 and inserted == 0, do: nil, else: item_type

          buildings =
            Map.put(buildings, storage_key, %{
              b
              | state: %{st | count: new_count, item_type: new_type}
            })

          cargo = List.duplicate(item_type, take)
          {cargo, buildings}
        else
          {[], buildings}
        end

      _ ->
        {[], buildings}
    end
  end

  defp deliver_to_site(site_key, cargo, buildings) do
    case Map.get(buildings, site_key) do
      %{state: %{construction: %{complete: false} = constr} = st} = b ->
        new_constr =
          Enum.reduce(cargo, constr, fn item, c ->
            case ConstructionCosts.deliver_item(c, item) do
              nil -> c
              updated -> updated
            end
          end)

        Map.put(buildings, site_key, %{b | state: %{st | construction: new_constr}})

      %{state: %{upgrade_progress: %{complete: false} = progress} = st} = b ->
        new_progress =
          Enum.reduce(cargo, progress, fn item, p ->
            case ConstructionCosts.deliver_item(p, item) do
              nil -> p
              updated -> updated
            end
          end)

        new_st =
          if new_progress.complete do
            # Auto-apply the upgrade
            state_field = new_progress.upgrade_name
            %{st | upgrade_progress: nil} |> Map.put(state_field, true)
          else
            %{st | upgrade_progress: new_progress}
          end

        Map.put(buildings, site_key, %{b | state: new_st})

      _ ->
        # Site no longer exists or is complete — drop cargo on ground
        for item <- cargo do
          GroundItems.add(site_key, item)
        end

        buildings
    end
  end

  defp upgrade_complete?(%{required: req, delivered: del}) do
    Enum.all?(req, fn {item, needed} -> Map.get(del, item, 0) >= needed end)
  end
end
