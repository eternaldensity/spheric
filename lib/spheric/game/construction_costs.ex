defmodule Spheric.Game.ConstructionCosts do
  @moduledoc """
  Building construction cost definitions and tier mapping.

  Each building type has a clearance tier and a resource cost.
  Buildings with `nil` cost are always free (gathering_post).
  """

  @costs %{
    # Tier 0 -- cheap basics (free via starter kit initially)
    conveyor: %{iron_ingot: 1},
    miner: %{iron_ingot: 2, copper_ingot: 1},
    smelter: %{iron_ingot: 3},
    submission_terminal: %{iron_ingot: 2, copper_ingot: 2},
    gathering_post: %{copper_ingot: 1},

    # Tier 1
    conveyor_mk2: %{iron_ingot: 2, copper_ingot: 1},
    splitter: %{iron_ingot: 3, copper_ingot: 2},
    merger: %{iron_ingot: 3, copper_ingot: 2},
    claim_beacon: %{iron_ingot: 5, copper_ingot: 3},
    trade_terminal: %{iron_ingot: 5, wire: 3},
    storage_container: %{iron_ingot: 5, plate: 2},
    assembler: %{iron_ingot: 8, copper_ingot: 5, titanium_ingot: 2},

    # Tier 2
    crossover: %{iron_ingot: 4, wire: 2},
    refinery: %{iron_ingot: 10, plate: 3, wire: 3},
    conveyor_mk3: %{iron_ingot: 3, wire: 2},
    balancer: %{iron_ingot: 5, circuit: 1},
    underground_conduit: %{iron_ingot: 8, copper_ingot: 5},

    # Tier 3
    containment_trap: %{frame: 2, circuit: 2, wire: 5},
    purification_beacon: %{frame: 3, circuit: 3, quartz_crystal: 5},
    defense_turret: %{frame: 3, plate: 5, circuit: 2},
    shadow_panel: %{frame: 2, quartz_crystal: 3, wire: 2},
    lamp: %{copper_ingot: 3, wire: 2, circuit: 1},

    # Tier 4
    bio_generator: %{frame: 3, motor: 2, cable: 3},
    substation: %{cable: 5, copper_ingot: 10, plate: 3},
    transfer_station: %{cable: 10, frame: 2, circuit: 3},
    advanced_smelter: %{heavy_frame: 1, circuit: 5, heat_sink: 3},

    # Tier 5
    advanced_assembler: %{heavy_frame: 2, advanced_circuit: 3, motor: 2},
    fabrication_plant: %{heavy_frame: 3, advanced_circuit: 5, motor: 3, cable: 5},
    essence_extractor: %{frame: 3, circuit: 5, quartz_crystal: 10},

    # Tier 6
    particle_collider: %{computer: 3, heavy_frame: 5, advanced_circuit: 5, motor_housing: 1},
    nuclear_refinery: %{composite: 5, computer: 2, heavy_frame: 3},

    # Tier 7
    dimensional_stabilizer: %{supercomputer: 2, advanced_composite: 5, containment_module: 1},
    paranatural_synthesizer: %{supercomputer: 3, advanced_composite: 3, nuclear_cell: 1},
    astral_projection_chamber: %{supercomputer: 2, containment_module: 2, astral_lens: 1},

    # Tier 8
    board_interface: %{dimensional_core: 2, supercomputer: 5, astral_lens: 3, advanced_composite: 10}
  }

  @tiers %{
    conveyor: 0,
    conveyor_mk2: 1,
    conveyor_mk3: 2,
    miner: 0,
    smelter: 0,
    submission_terminal: 0,
    gathering_post: 0,
    splitter: 1,
    merger: 1,
    claim_beacon: 1,
    trade_terminal: 1,
    storage_container: 1,
    assembler: 1,
    crossover: 2,
    refinery: 2,
    balancer: 2,
    underground_conduit: 2,
    containment_trap: 3,
    purification_beacon: 3,
    defense_turret: 3,
    shadow_panel: 3,
    lamp: 3,
    bio_generator: 4,
    substation: 4,
    transfer_station: 4,
    advanced_smelter: 4,
    advanced_assembler: 5,
    fabrication_plant: 5,
    essence_extractor: 5,
    particle_collider: 6,
    nuclear_refinery: 6,
    dimensional_stabilizer: 7,
    paranatural_synthesizer: 7,
    astral_projection_chamber: 7,
    board_interface: 8
  }

  @doc "Returns the construction cost for a building type, or nil if free."
  def cost(type), do: Map.get(@costs, type)

  @doc "Returns the clearance tier for a building type."
  def tier(type), do: Map.get(@tiers, type, 0)

  @doc "Returns all costs (for recipe browser display)."
  def all_costs, do: @costs

  @doc "Returns all tier mappings."
  def all_tiers, do: @tiers

  @doc "Check if a building type is always free (no construction cost ever)."
  def always_free?(type), do: Map.get(@costs, type) == nil

  @doc """
  Create initial construction state for a building.
  Returns nil if the building is free, otherwise returns the construction map.
  """
  def initial_construction(type) do
    case cost(type) do
      nil ->
        nil

      cost_map ->
        %{
          required: cost_map,
          delivered: Map.new(cost_map, fn {item, _count} -> {item, 0} end),
          complete: false
        }
    end
  end

  @doc "Check if construction is complete."
  def construction_complete?(nil), do: true
  def construction_complete?(%{complete: true}), do: true

  def construction_complete?(%{required: required, delivered: delivered}) do
    Enum.all?(required, fn {item, count} ->
      Map.get(delivered, item, 0) >= count
    end)
  end

  @doc "Check if a construction site still needs a specific item type."
  def needs_item?(nil, _item), do: false
  def needs_item?(%{complete: true}, _item), do: false

  def needs_item?(%{required: required, delivered: delivered}, item) do
    case Map.get(required, item) do
      nil -> false
      needed -> Map.get(delivered, item, 0) < needed
    end
  end

  @doc "Try to deliver an item to a construction site. Returns updated construction or nil."
  def deliver_item(nil, _item), do: nil

  def deliver_item(%{complete: true} = construction, _item), do: construction

  def deliver_item(%{required: required, delivered: delivered} = construction, item) do
    case Map.get(required, item) do
      nil ->
        nil

      needed ->
        current = Map.get(delivered, item, 0)

        if current < needed do
          new_delivered = Map.put(delivered, item, current + 1)
          new_construction = %{construction | delivered: new_delivered}

          if construction_complete?(new_construction) do
            %{new_construction | complete: true}
          else
            new_construction
          end
        else
          nil
        end
    end
  end
end
