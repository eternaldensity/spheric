defmodule Spheric.Game.Power do
  @moduledoc """
  Power network resolution.

  Manages the power distribution network: generators produce power,
  substations distribute it locally, transfer stations bridge long distances.

  Power state is resolved every 5 ticks and cached for O(1) lookups.
  """

  alias Spheric.Game.WorldStore
  alias Spheric.Game.Behaviors.{BioGenerator, ShadowPanel, Substation, TransferStation}

  @table :spheric_power_cache
  @resolve_interval 5

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Check if a building at key is powered. O(1) ETS lookup."
  def powered?(key) do
    case :ets.whereis(@table) do
      :undefined ->
        false

      _ ->
        case :ets.lookup(@table, key) do
          [{^key, true}] -> true
          _ -> false
        end
    end
  end

  @doc "Resolve the power network. Called every @resolve_interval ticks."
  def maybe_resolve(tick) do
    if rem(tick, @resolve_interval) == 0 do
      resolve()
    end
  end

  @doc "Full power network resolution. BFS from fueled generators through substations."
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
      # BFS: find all substations/transfer_stations reachable from fueled generators
      powered_nodes = bfs_power_network(fueled_generators, substations, transfer_stations)

      # Mark all machines within powered substation radius as powered
      powered_substations =
        Enum.filter(powered_nodes, fn key ->
          building = WorldStore.get_building(key)
          building && building.type == :substation
        end)

      all_buildings = gather_all_buildings()

      for sub_key <- powered_substations,
          {machine_key, _building} <- all_buildings,
          within_radius?(sub_key, machine_key, Substation.radius()) do
        :ets.insert(@table, {machine_key, true})
      end

      # Also mark generators and substations themselves as powered
      for key <- powered_nodes do
        :ets.insert(@table, {key, true})
      end

      :ok
    end
  end

  @doc "Clear power cache."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end
  end

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

  # BFS from fueled generators through the power network
  defp bfs_power_network(fueled_generators, substations, transfer_stations) do
    # Seed: substations within generator radius (3) of a fueled generator
    gen_radius = 3

    initial_powered =
      for {gen_key, _} <- fueled_generators,
          {sub_key, _} <- substations,
          within_radius?(gen_key, sub_key, gen_radius),
          into: MapSet.new(),
          do: sub_key

    # BFS through substations and transfer stations
    all_nodes = substations ++ transfer_stations
    bfs_expand(initial_powered, initial_powered, all_nodes)
  end

  defp bfs_expand(frontier, visited, all_nodes) do
    new_frontier =
      for frontier_key <- frontier,
          {node_key, node_building} <- all_nodes,
          not MapSet.member?(visited, node_key),
          connectable?(frontier_key, node_key, node_building),
          into: MapSet.new(),
          do: node_key

    if MapSet.size(new_frontier) == 0 do
      visited
    else
      bfs_expand(new_frontier, MapSet.union(visited, new_frontier), all_nodes)
    end
  end

  # Check if two power nodes can connect based on their types and radii
  defp connectable?(from_key, to_key, to_building) do
    from_building = WorldStore.get_building(from_key)

    cond do
      from_building == nil ->
        false

      # Substations connect to other substations within substation radius
      from_building.type == :substation and to_building.type == :substation ->
        within_radius?(from_key, to_key, Substation.radius())

      # Substations connect to transfer stations within substation radius
      from_building.type == :substation and to_building.type == :transfer_station ->
        within_radius?(from_key, to_key, Substation.radius())

      # Transfer stations connect to substations within transfer radius
      from_building.type == :transfer_station and to_building.type == :substation ->
        within_radius?(from_key, to_key, TransferStation.radius())

      # Transfer stations connect to other transfer stations within transfer radius
      from_building.type == :transfer_station and to_building.type == :transfer_station ->
        within_radius?(from_key, to_key, TransferStation.radius())

      true ->
        false
    end
  end

  defp within_radius?({f1, r1, c1}, {f2, r2, c2}, radius) do
    f1 == f2 and abs(r1 - r2) <= radius and abs(c1 - c2) <= radius
  end
end
