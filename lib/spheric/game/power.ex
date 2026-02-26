defmodule Spheric.Game.Power do
  @moduledoc """
  Capacity-based power network resolution.

  Manages the power distribution network: generators produce wattage,
  substations distribute it locally, transfer stations bridge long distances.
  Each isolated substation cluster forms its own network with independent
  capacity (total generator watts) and load (total building draw).

  When a network is overloaded (load > capacity), all buildings in that
  network experience proportional brownout (slowdown).

  Power state is resolved every 5 ticks and cached for O(1) lookups.
  """

  alias Spheric.Game.{WorldStore, ConstructionCosts}
  alias Spheric.Game.Behaviors.{BioGenerator, ShadowPanel, Substation, TransferStation}

  @table :spheric_power_cache
  @resolve_interval 5
  @gen_radius 3

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Check if a building at key is connected to a power network. O(1) ETS lookup."
  def powered?(key) do
    case :ets.whereis(@table) do
      :undefined ->
        false

      _ ->
        case :ets.lookup(@table, key) do
          [{^key, _network_id}] -> true
          _ -> false
        end
    end
  end

  @doc """
  Get power network stats for a building's network.
  Returns %{capacity: integer, load: integer} or nil if disconnected.
  """
  def network_stats(key) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@table, key) do
          [{^key, network_id}] ->
            case :ets.lookup(@table, {:network, network_id}) do
              [{{:network, ^network_id}, stats}] -> stats
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end

  @doc """
  Get the load ratio for a building's network.
  Returns a float >= 1.0 when overloaded, 1.0 when at or under capacity,
  or nil if the building is not connected to any network.
  """
  def load_ratio(key) do
    case network_stats(key) do
      %{capacity: cap, load: load} when cap > 0 ->
        if load > cap, do: load / cap, else: 1.0

      %{capacity: 0} ->
        # Network exists but has no active generators (all ran out of fuel)
        nil

      _ ->
        nil
    end
  end

  @doc "Resolve the power network. Called every @resolve_interval ticks."
  def maybe_resolve(tick) do
    if rem(tick, @resolve_interval) == 0 do
      resolve()
    end
  end

  @doc "Full power network resolution with capacity-based tracking."
  def resolve do
    # Clear cache
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    # Gather all power-relevant buildings
    {generators, substations, transfer_stations} = gather_power_buildings()

    # Find fueled generators
    fueled_generators =
      Enum.filter(generators, fn {_key, building} ->
        case building.type do
          :bio_generator -> BioGenerator.producing_power?(building.state)
          :shadow_panel -> ShadowPanel.producing_power?(building.state)
          _ -> false
        end
      end)

    if fueled_generators == [] do
      :ok
    else
      all_power_nodes = substations ++ transfer_stations
      all_buildings = gather_all_buildings()
      buildings_map = Map.new(all_buildings)

      # Find connected components among power nodes
      components = find_connected_components(all_power_nodes)

      # For each component, check if any fueled generator seeds into it
      components
      |> Enum.with_index()
      |> Enum.each(fn {component_keys, network_id} ->
        # Filter to substations in this component (generators only seed substations)
        component_substations =
          Enum.filter(component_keys, fn key ->
            building = WorldStore.get_building(key)
            building && building.type == :substation
          end)

        # Find generators that seed into this component
        seeding_generators =
          Enum.filter(fueled_generators, fn {gen_key, _gen} ->
            Enum.any?(component_substations, fn sub_key ->
              within_radius?(gen_key, sub_key, @gen_radius)
            end)
          end)

        if seeding_generators != [] do
          # Sum generator wattage = capacity
          # Use actual state output for shadow panels (varies with illumination),
          # static max for other generators.
          capacity =
            Enum.reduce(seeding_generators, 0, fn {_key, gen}, acc ->
              case gen.type do
                :shadow_panel -> acc + (gen.state[:power_output] || 0)
                _ -> acc + ConstructionCosts.power_output(gen.type)
              end
            end)

          # Find all buildings within powered substation radius
          powered_keys =
            for sub_key <- component_substations,
                {bld_key, _bld} <- all_buildings,
                within_radius?(sub_key, bld_key, Substation.radius()),
                into: MapSet.new(),
                do: bld_key

          # Sum building power draw = load
          # Exclude user-toggled-off buildings and buildings under construction
          load =
            Enum.reduce(powered_keys, 0, fn bld_key, acc ->
              case Map.get(buildings_map, bld_key) do
                nil ->
                  acc

                bld ->
                  if bld.state[:powered] == false or
                       (bld.state[:construction] && bld.state.construction[:complete] == false) do
                    acc
                  else
                    acc + ConstructionCosts.power_draw(bld.type)
                  end
              end
            end)

          # Write network stats
          :ets.insert(@table, {{:network, network_id}, %{capacity: capacity, load: load}})

          # Write per-building membership for all powered buildings
          for key <- powered_keys do
            :ets.insert(@table, {key, network_id})
          end

          # Also mark generators and power nodes as part of the network
          for {gen_key, _} <- seeding_generators do
            :ets.insert(@table, {gen_key, network_id})
          end

          for node_key <- component_keys do
            :ets.insert(@table, {node_key, network_id})
          end
        end
      end)

      :ok
    end
  end

  @doc "Clear power cache."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end
  end

  # -- Private helpers --

  # Gather all power-related buildings grouped by type
  defp gather_power_buildings do
    all = gather_all_buildings()

    generators = Enum.filter(all, fn {_k, b} -> b.type in [:bio_generator, :shadow_panel] end)
    substations = Enum.filter(all, fn {_k, b} -> b.type == :substation end)
    transfers = Enum.filter(all, fn {_k, b} -> b.type == :transfer_station end)

    {generators, substations, transfers}
  end

  defp gather_all_buildings do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        do: {key, building}
  end

  # Find connected components among power nodes (substations + transfer stations).
  # Returns a list of lists, where each inner list is a set of keys in one component.
  defp find_connected_components(nodes) do
    # Build a map from key to building for quick lookup
    node_map = Map.new(nodes, fn {key, building} -> {key, building} end)
    all_keys = Map.keys(node_map)

    # Iterative flood fill to find connected components
    {components, _visited} =
      Enum.reduce(all_keys, {[], MapSet.new()}, fn key, {comps, visited} ->
        if MapSet.member?(visited, key) do
          {comps, visited}
        else
          # BFS from this unvisited node
          {component, new_visited} = bfs_component(key, node_map, visited)
          {[component | comps], new_visited}
        end
      end)

    components
  end

  # BFS to find all nodes in the same connected component as start_key.
  defp bfs_component(start_key, node_map, visited) do
    bfs_expand_component(
      [start_key],
      MapSet.put(visited, start_key),
      [start_key],
      node_map
    )
  end

  defp bfs_expand_component([], visited, component, _node_map) do
    {component, visited}
  end

  defp bfs_expand_component(frontier, visited, component, node_map) do
    new_frontier =
      for frontier_key <- frontier,
          {node_key, node_building} <- node_map,
          not MapSet.member?(visited, node_key),
          connectable?(frontier_key, node_key, node_building, node_map),
          do: node_key

    new_frontier = Enum.uniq(new_frontier)
    new_visited = Enum.reduce(new_frontier, visited, &MapSet.put(&2, &1))
    new_component = component ++ new_frontier

    bfs_expand_component(new_frontier, new_visited, new_component, node_map)
  end

  # Check if two power nodes can connect based on their types and radii
  defp connectable?(from_key, to_key, to_building, node_map) do
    case Map.get(node_map, from_key) do
      nil ->
        false

      from_building ->
        cond do
          from_building.type == :substation and to_building.type == :substation ->
            within_radius?(from_key, to_key, Substation.radius())

          from_building.type == :substation and to_building.type == :transfer_station ->
            within_radius?(from_key, to_key, Substation.radius())

          from_building.type == :transfer_station and to_building.type == :substation ->
            within_radius?(from_key, to_key, TransferStation.radius())

          from_building.type == :transfer_station and to_building.type == :transfer_station ->
            within_radius?(from_key, to_key, TransferStation.radius())

          true ->
            false
        end
    end
  end

  defp within_radius?({f1, r1, c1}, {f2, r2, c2}, radius) do
    f1 == f2 and abs(r1 - r2) <= radius and abs(c1 - c2) <= radius
  end
end
