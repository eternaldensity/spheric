defmodule SphericWeb.GameLive.Helpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Spheric.Game.{
    WorldStore,
    Buildings,
    Behaviors,
    Research,
    Creatures,
    Lore,
    AlteredItems,
    Hiss,
    Territory,
    Persistence,
    GroundItems,
    ConstructionCosts
  }

  alias SphericWeb.Presence

  def build_face_terrain(face_id, subdivisions) do
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

  def refresh_research(socket) do
    world_id = socket.assigns.world_id
    player_id = socket.assigns.player_id

    if world_id do
      research_summary = Research.progress_summary(world_id, player_id)
      clearance = Research.clearance_level(player_id)
      unlocked = Research.unlocked_buildings(player_id)

      socket =
        socket
        |> assign(:research_summary, research_summary)
        |> assign(:clearance_level, clearance)
        |> assign(:building_types, unlocked)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def direction_label(0), do: "W"
  def direction_label(1), do: "S"
  def direction_label(2), do: "E"
  def direction_label(3), do: "N"

  def build_tile_info({face, row, col} = key) do
    tile = WorldStore.get_tile(key)
    building = WorldStore.get_building(key)

    {resource_type, resource_amount} =
      case tile do
        %{resource: {type, amount}} -> {Atom.to_string(type), amount}
        _ -> {nil, nil}
      end

    ground_items = GroundItems.get(key)
    altered_item = AlteredItems.get(key)
    corruption = Hiss.corruption_at(key)
    territory = Territory.territory_at(key)

    territory_info =
      if territory do
        owner_name = Persistence.get_player_name(territory.owner_id)
        %{owner_id: territory.owner_id, owner_name: owner_name || "Unknown"}
      else
        nil
      end

    base = %{
      face: face,
      row: row,
      col: col,
      terrain: Atom.to_string(tile.terrain),
      resource: tile.resource,
      resource_type: resource_type,
      resource_amount: resource_amount,
      building: building,
      ground_items: ground_items,
      altered_item: altered_item,
      corruption: corruption,
      territory: territory_info
    }

    if building do
      owner_name = Persistence.get_player_name(building[:owner_id])

      drone_bay_info =
        if building.type == :drone_bay do
          player_upgrades = Persistence.get_drone_upgrades(building[:owner_id])

          %{
            mode: building.state[:mode] || :idle,
            selected_upgrade: building.state[:selected_upgrade],
            delivered: building.state[:delivered] || %{},
            required: building.state[:required] || %{},
            fuel_buffer_count: length(building.state[:fuel_buffer] || []),
            upgrade_costs: Behaviors.DroneBay.all_upgrade_costs(),
            player_upgrades: player_upgrades
          }
        else
          nil
        end

      Map.merge(base, %{
        building_name: Lore.display_name(building.type),
        building_orientation: building.orientation,
        building_status: building_status_text(building),
        building_owner_id: building[:owner_id],
        building_owner_name: owner_name,
        drone_bay_info: drone_bay_info
      })
    else
      Map.merge(base, %{
        building_name: nil,
        building_orientation: nil,
        building_status: nil,
        building_owner_id: nil,
        building_owner_name: nil,
        drone_bay_info: nil
      })
    end
  end

  def building_status_text(%{state: %{construction: %{complete: false} = constr}}) do
    total_required =
      Enum.reduce(constr.required, 0, fn {_item, qty}, acc -> acc + qty end)

    total_delivered =
      Enum.reduce(constr.delivered, 0, fn {_item, qty}, acc -> acc + qty end)

    needed =
      Enum.flat_map(constr.required, fn {item, qty} ->
        delivered = Map.get(constr.delivered, item, 0)
        remaining = qty - delivered
        if remaining > 0, do: ["#{remaining} #{Lore.display_name(item)}"], else: []
      end)

    "Under construction (#{total_delivered}/#{total_required}) — needs #{Enum.join(needed, ", ")}"
  end

  def building_status_text(%{state: %{powered: false}}) do
    "OFFLINE"
  end

  def building_status_text(%{type: :miner, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:progress] > 0 -> "Extracting... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  def building_status_text(%{type: :smelter, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:input_buffer] != nil -> "Processing... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  def building_status_text(%{type: :conveyor, state: state}) do
    if state[:item], do: "Carrying: #{Lore.display_name(state.item)}", else: "Empty"
  end

  def building_status_text(%{type: :conveyor_mk2, state: state}) do
    count = if(state[:item], do: 1, else: 0) + if state[:buffer], do: 1, else: 0
    if count > 0, do: "Carrying: #{count}/2 items", else: "Empty"
  end

  def building_status_text(%{type: :conveyor_mk3, state: state}) do
    count =
      if(state[:item], do: 1, else: 0) + if(state[:buffer1], do: 1, else: 0) +
        if state[:buffer2], do: 1, else: 0

    if count > 0, do: "Carrying: #{count}/3 items", else: "Empty"
  end

  def building_status_text(%{type: :assembler, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)}"

      state[:input_a] != nil and state[:input_b] != nil ->
        "Fabricating... #{state.progress}/#{state.rate}"

      state[:input_a] != nil ->
        "Input A: #{Lore.display_name(state.input_a)} (awaiting B)"

      state[:input_b] != nil ->
        "Input B: #{Lore.display_name(state.input_b)} (awaiting A)"

      true ->
        "Idle"
    end
  end

  def building_status_text(%{type: :refinery, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:input_buffer] != nil -> "Distilling... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  def building_status_text(%{type: :submission_terminal, state: state}) do
    cond do
      state[:input_buffer] != nil ->
        "Receiving: #{Lore.display_name(state.input_buffer)}"

      state[:last_submitted] != nil ->
        "Last: #{Lore.display_name(state.last_submitted)} (#{state.total_submitted} total)"

      true ->
        "Awaiting submissions"
    end
  end

  def building_status_text(%{type: :containment_trap, state: state}) do
    cond do
      state[:capturing] != nil ->
        "Containing... #{state.capture_progress}/15"

      true ->
        "Scanning for entities"
    end
  end

  def building_status_text(%{type: :purification_beacon, state: state}) do
    "Active — Radius #{state[:radius] || 5}"
  end

  def building_status_text(%{type: :defense_turret, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)} (#{state[:kills] || 0} kills)"

      (state[:kills] || 0) > 0 ->
        "Scanning — #{state.kills} kills"

      true ->
        "Scanning for hostiles"
    end
  end

  def building_status_text(%{type: :claim_beacon, state: state}) do
    "Active — Radius #{state[:radius] || 8}"
  end

  def building_status_text(%{type: :storage_container, state: state}) do
    if state[:item_type] do
      "#{Lore.display_name(state.item_type)}: #{state.count}/#{state.capacity}"
    else
      "Empty — 0/#{state[:capacity] || 100}"
    end
  end

  def building_status_text(%{type: :underground_conduit, state: state}) do
    cond do
      state[:item] != nil -> "Carrying: #{Lore.display_name(state.item)}"
      state[:linked_to] != nil -> "Linked to #{format_building_key(state.linked_to)}"
      true -> "Unlinked — select another conduit to pair"
    end
  end

  def building_status_text(%{type: :crossover, state: state}) do
    h = if state[:horizontal], do: Lore.display_name(state.horizontal), else: nil
    v = if state[:vertical], do: Lore.display_name(state.vertical), else: nil

    case {h, v} do
      {nil, nil} -> "Empty"
      {h, nil} -> "H: #{h}"
      {nil, v} -> "V: #{v}"
      {h, v} -> "H: #{h} | V: #{v}"
    end
  end

  def building_status_text(%{type: :balancer, state: state}) do
    cond do
      state[:item] != nil -> "Routing: #{Lore.display_name(state.item)}"
      true -> "Idle — balancing output"
    end
  end

  def building_status_text(%{type: :trade_terminal, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)}"

      state[:trade_id] != nil ->
        "Linked — #{state.total_sent} sent, #{state.total_received} received"

      true ->
        "No requisition linked"
    end
  end

  def building_status_text(%{type: :dimensional_stabilizer, state: state}) do
    "Active — Immunity Radius #{state[:radius] || 15}"
  end

  def building_status_text(%{type: :astral_projection_chamber, state: _state}) do
    "Ready — Click to project"
  end

  def building_status_text(%{type: :gathering_post, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:visitor_type] != nil -> "Attracting... #{state.progress}/#{state.rate}"
      true -> "Scanning for entities"
    end
  end

  def building_status_text(%{type: :drone_bay, state: state}) do
    case state[:mode] do
      :accepting -> "Installing upgrade... feed items"
      :complete -> "Upgrade ready"
      _ ->
        buf_count = length(state[:fuel_buffer] || [])
        if buf_count > 0, do: "Fuel buffer: #{buf_count}/5", else: "Idle"
    end
  end

  def building_status_text(_building), do: nil

  def upgrade_display_name(:auto_refuel), do: "Auto-Refuel"
  def upgrade_display_name(:expanded_tank), do: "Expanded Tank"
  def upgrade_display_name(:drone_spotlight), do: "Drone Spotlight"
  def upgrade_display_name(other), do: other |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  def creature_boost_label(type) do
    case Creatures.boost_info(type) do
      nil -> ""
      %{type: :speed, amount: amt} -> "Speed +#{round(amt * 100)}%"
      %{type: :efficiency, amount: amt} -> "Efficiency +#{round(amt * 100)}%"
      %{type: :output, amount: amt} -> "Output +#{round(amt * 100)}%"
      %{type: :area, amount: amt} -> "Area +#{round(amt * 100)}%"
      %{type: :defense, amount: _amt} -> "Defense"
      %{type: :all, amount: amt} -> "All +#{round(amt * 100)}%"
      _ -> ""
    end
  end

  def world_event_label(:hiss_surge), do: "ALERT: Hiss Surge Active"
  def world_event_label(:meteor_shower), do: "EVENT: Meteor Shower"
  def world_event_label(:resonance_cascade), do: "EVENT: Resonance Cascade"
  def world_event_label(:entity_migration), do: "EVENT: Entity Migration"
  def world_event_label(_), do: "EVENT: Unknown"

  def shift_phase_label(:dawn), do: "Dawn Shift"
  def shift_phase_label(:zenith), do: "Zenith Shift"
  def shift_phase_label(:dusk), do: "Dusk Shift"
  def shift_phase_label(:nadir), do: "Nadir Shift"
  def shift_phase_label(_), do: "Unknown Shift"

  def shift_phase_color(:dawn), do: "var(--fbc-highlight)"
  def shift_phase_color(:zenith), do: "var(--fbc-info)"
  def shift_phase_color(:dusk), do: "var(--fbc-accent)"
  def shift_phase_color(:nadir), do: "#6688AA"
  def shift_phase_color(_), do: "var(--fbc-text-dim)"

  def trade_status_color("open"), do: "var(--fbc-info)"
  def trade_status_color("accepted"), do: "var(--fbc-highlight)"
  def trade_status_color("completed"), do: "var(--fbc-success)"
  def trade_status_color("cancelled"), do: "var(--fbc-accent)"
  def trade_status_color(_), do: "var(--fbc-text-dim)"

  def format_building_key({face, row, col}), do: "F#{face} R#{row} C#{col}"
  def format_building_key(_), do: "—"

  def catalog_buildings(category, unlocked_types) do
    Buildings.buildings_by_category()
    |> Enum.find(fn {cat, _} -> cat == category end)
    |> case do
      {_, types} -> Enum.filter(types, &(&1 in unlocked_types))
      nil -> []
    end
  end

  def restore_hotbar(params, unlocked_buildings) do
    case params["hotbar"] do
      raw when is_binary(raw) and raw != "" ->
        case Jason.decode(raw) do
          {:ok, list} when is_list(list) ->
            list
            |> Enum.take(5)
            |> Enum.map(fn
              nil -> nil
              "" -> nil
              s when is_binary(s) ->
                atom = String.to_existing_atom(s)
                if atom in unlocked_buildings, do: atom, else: nil
            end)
            |> then(fn slots -> slots ++ List.duplicate(nil, 5 - length(slots)) end)

          _ ->
            Buildings.default_hotbar()
        end

      _ ->
        Buildings.default_hotbar()
    end
  rescue
    _ -> Buildings.default_hotbar()
  end

  def restore_waypoints(params) do
    case params["waypoints"] do
      raw when is_binary(raw) and raw != "" ->
        case Jason.decode(raw) do
          {:ok, list} when is_list(list) ->
            list
            |> Enum.filter(fn wp ->
              is_map(wp) and is_binary(wp["name"]) and
                is_integer(wp["face"]) and is_integer(wp["row"]) and is_integer(wp["col"])
            end)
            |> Enum.take(50)

          _ ->
            []
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def restore_player(params) do
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

  def to_float(val, _default) when is_float(val), do: val
  def to_float(val, _default) when is_integer(val), do: val * 1.0
  def to_float(nil, default), do: default
  def to_float(_, default), do: default

  def to_int(v) when is_integer(v), do: v
  def to_int(v) when is_binary(v), do: String.to_integer(v)

  def build_buildings_snapshot do
    for face_id <- 0..29,
        {{f, r, c}, building} <- WorldStore.get_face_buildings(face_id) do
      base = %{
        face: f,
        row: r,
        col: c,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      }

      case building.state do
        %{construction: %{complete: false}} -> Map.put(base, :under_construction, true)
        _ -> base
      end
    end
  end

  @doc "Format cost string for a building type, considering starter kit."
  def building_cost_label(type, starter_kit_remaining) do
    free_count = Map.get(starter_kit_remaining, type, 0)

    if free_count > 0 do
      "Free (#{free_count} left)"
    else
      case ConstructionCosts.cost(type) do
        nil -> "Free"
        cost_map -> format_cost_map(cost_map)
      end
    end
  end

  @doc "Format a cost map into a display string."
  def format_cost_map(cost_map) do
    cost_map
    |> Enum.map(fn {item, qty} -> "#{qty} #{Lore.display_name(item)}" end)
    |> Enum.join(", ")
  end
end
