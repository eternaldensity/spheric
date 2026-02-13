defmodule Spheric.Game.TickProcessor do
  @moduledoc """
  Per-tick simulation pipeline.

  Called by WorldServer every tick (200ms). Processes all buildings in
  a fixed order to ensure deterministic behavior:

  1. Miners: extract resources, fill output buffer
  2. Smelters: process input buffers, fill output buffer
  3. Push resolution: move items from outputs/conveyors to downstream buildings

  Returns `{tick, items_by_face}` where `items_by_face` is a map of
  `face_id => [item_update]` for broadcasting to clients.
  """

  alias Spheric.Game.{WorldStore, Behaviors}
  alias Spheric.Geometry.TileNeighbors

  @doc """
  Process one tick. Returns `{tick, items_by_face}`.
  """
  def process_tick(tick) do
    buildings = gather_all_buildings()

    {miners, _conveyors, smelters, _others} = classify(buildings)

    # Phase 1: Miners tick
    miner_updates =
      Enum.map(miners, fn {key, building} ->
        {key, Behaviors.Miner.tick(key, building)}
      end)

    # Phase 2: Smelters tick
    smelter_updates =
      Enum.map(smelters, fn {key, building} ->
        {key, Behaviors.Smelter.tick(key, building)}
      end)

    # Merge updates into the full building map
    all_buildings = merge_updates(buildings, miner_updates ++ smelter_updates)

    # Phase 3: Push resolution — move items between buildings
    {final_buildings, movements} = resolve_pushes(all_buildings)

    # Batch write all modified building states to ETS
    write_changes(buildings, final_buildings)

    # Build per-face item state for broadcasting
    items_by_face = build_item_snapshot(final_buildings, movements)

    {tick, items_by_face}
  end

  defp gather_all_buildings do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        into: %{} do
      {key, building}
    end
  end

  defp classify(buildings) do
    Enum.reduce(buildings, {[], [], [], []}, fn {key, building}, {m, c, s, o} ->
      case building.type do
        :miner -> {[{key, building} | m], c, s, o}
        :conveyor -> {m, [{key, building} | c], s, o}
        :smelter -> {m, c, [{key, building} | s], o}
        _ -> {m, c, s, [{key, building} | o]}
      end
    end)
  end

  defp merge_updates(buildings, updates) do
    Enum.reduce(updates, buildings, fn {key, building}, acc ->
      Map.put(acc, key, building)
    end)
  end

  @doc """
  Resolve item movement. Returns `{final_buildings, movements}`.

  `movements` is a list of `{source_key, dest_key, item_type}`.
  """
  def resolve_pushes(buildings) do
    n = Application.get_env(:spheric, :subdivisions, 16)

    # Collect push requests from all buildings that have items to push
    push_requests =
      buildings
      |> Enum.flat_map(fn {key, building} ->
        case get_push_request(key, building, n) do
          nil -> []
          request -> [request]
        end
      end)

    # Group by destination to detect conflicts
    by_dest = Enum.group_by(push_requests, fn {_src, dest, _item} -> dest end)

    # For each destination, accept at most one item
    accepted =
      Enum.flat_map(by_dest, fn {dest_key, requests} ->
        dest_building = Map.get(buildings, dest_key)

        case try_accept(dest_building, requests) do
          nil -> []
          winner -> [winner]
        end
      end)

    # Apply accepted pushes
    final = apply_pushes(buildings, accepted)
    {final, accepted}
  end

  defp get_push_request(key, %{type: :conveyor, orientation: dir, state: %{item: item}}, n)
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(key, %{type: :miner, orientation: dir, state: %{output_buffer: item}}, n)
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(
         key,
         %{type: :smelter, orientation: dir, state: %{output_buffer: item}},
         n
       )
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(
         key,
         %{type: :splitter, orientation: dir, state: %{item: item, next_output: side}},
         n
       )
       when not is_nil(item) do
    {left, right} = Behaviors.Splitter.output_directions(dir)
    output_dir = if side == :left, do: left, else: right

    case TileNeighbors.neighbor(key, output_dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(key, %{type: :merger, orientation: dir, state: %{item: item}}, n)
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(_key, _building, _n), do: nil

  # Try to accept an item at the destination building
  defp try_accept(nil, _requests), do: nil

  defp try_accept(%{type: :conveyor, state: %{item: nil}}, [winner | _]), do: winner

  defp try_accept(%{type: :smelter, state: %{input_buffer: nil}}, [winner | _]), do: winner

  defp try_accept(%{type: :splitter, state: %{item: nil}}, [winner | _]), do: winner

  defp try_accept(%{type: :merger, state: %{item: nil}}, [winner | _]), do: winner

  defp try_accept(_building, _requests), do: nil

  defp apply_pushes(buildings, accepted) do
    Enum.reduce(accepted, buildings, fn {src_key, dest_key, item}, acc ->
      # Clear source output
      acc =
        Map.update!(acc, src_key, fn b ->
          case b.type do
            :conveyor -> %{b | state: %{b.state | item: nil}}
            :miner -> %{b | state: %{b.state | output_buffer: nil}}
            :smelter -> %{b | state: %{b.state | output_buffer: nil}}
            :splitter ->
              next = if b.state.next_output == :left, do: :right, else: :left
              %{b | state: %{b.state | item: nil, next_output: next}}
            :merger -> %{b | state: %{b.state | item: nil}}
            _ -> b
          end
        end)

      # Set destination input
      Map.update!(acc, dest_key, fn b ->
        case b.type do
          :conveyor -> %{b | state: %{b.state | item: item}}
          :smelter -> %{b | state: %{b.state | input_buffer: item}}
          :splitter -> %{b | state: %{b.state | item: item}}
          :merger -> %{b | state: %{b.state | item: item}}
          _ -> b
        end
      end)
    end)
  end

  # Only write buildings whose state actually changed
  defp write_changes(original, final) do
    Enum.each(final, fn {key, building} ->
      case Map.get(original, key) do
        ^building -> :noop
        _ -> WorldStore.put_building(key, building)
      end
    end)
  end

  # Build per-face item snapshot for client rendering.
  # Includes all items currently held by buildings (conveyors, miner/smelter buffers).
  # For items that moved this tick, includes the source position for interpolation.
  defp build_item_snapshot(buildings, movements) do
    # Build a lookup of destination -> source for items that moved
    movement_sources =
      Map.new(movements, fn {src_key, dest_key, _item} ->
        {dest_key, src_key}
      end)

    buildings
    |> Enum.flat_map(fn {key, building} ->
      items_from_building(key, building, movement_sources)
    end)
    |> Enum.group_by(fn item -> item.face end)
  end

  defp items_from_building({face, row, col}, %{type: :conveyor, state: %{item: item}}, sources)
       when not is_nil(item) do
    from = Map.get(sources, {face, row, col})

    [
      %{
        face: face,
        row: row,
        col: col,
        item: item,
        from_face: if(from, do: elem(from, 0)),
        from_row: if(from, do: elem(from, 1)),
        from_col: if(from, do: elem(from, 2))
      }
    ]
  end

  defp items_from_building({face, row, col}, %{type: :miner, state: %{output_buffer: item}}, _)
       when not is_nil(item) do
    [%{face: face, row: row, col: col, item: item, from_face: nil, from_row: nil, from_col: nil}]
  end

  defp items_from_building(
         {face, row, col},
         %{type: :smelter, state: %{output_buffer: item}},
         _
       )
       when not is_nil(item) do
    [%{face: face, row: row, col: col, item: item, from_face: nil, from_row: nil, from_col: nil}]
  end

  defp items_from_building({face, row, col}, %{type: :splitter, state: %{item: item}}, sources)
       when not is_nil(item) do
    from = Map.get(sources, {face, row, col})

    [
      %{
        face: face,
        row: row,
        col: col,
        item: item,
        from_face: if(from, do: elem(from, 0)),
        from_row: if(from, do: elem(from, 1)),
        from_col: if(from, do: elem(from, 2))
      }
    ]
  end

  defp items_from_building({face, row, col}, %{type: :merger, state: %{item: item}}, sources)
       when not is_nil(item) do
    from = Map.get(sources, {face, row, col})

    [
      %{
        face: face,
        row: row,
        col: col,
        item: item,
        from_face: if(from, do: elem(from, 0)),
        from_row: if(from, do: elem(from, 1)),
        from_col: if(from, do: elem(from, 2))
      }
    ]
  end

  defp items_from_building(_key, _building, _sources), do: []
end
