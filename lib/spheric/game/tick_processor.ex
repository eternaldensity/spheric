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

  alias Spheric.Game.{WorldStore, Behaviors, Creatures, ObjectsOfPower, Statistics, ShiftCycle}
  alias Spheric.Geometry.TileNeighbors

  require Logger

  @doc """
  Process one tick. Returns `{tick, items_by_face}`.
  """
  def process_tick(tick) do
    buildings = gather_all_buildings()

    {miners, _conveyors, smelters, assemblers, refineries, terminals, trade_terminals, _others} =
      classify(buildings)

    # Phase 1: Miners tick (with creature boost)
    miner_updates =
      Enum.map(miners, fn {key, building} ->
        updated = Behaviors.Miner.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2: Smelters tick (with creature boost)
    smelter_updates =
      Enum.map(smelters, fn {key, building} ->
        updated = Behaviors.Smelter.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2b: Refineries tick (with creature boost)
    refinery_updates =
      Enum.map(refineries, fn {key, building} ->
        updated = Behaviors.Refinery.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2c: Assemblers tick (with creature boost)
    assembler_updates =
      Enum.map(assemblers, fn {key, building} ->
        updated = Behaviors.Assembler.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2d: Submission terminals tick (consume items, report submissions)
    {terminal_updates, submissions} =
      Enum.reduce(terminals, {[], []}, fn {key, building}, {updates, subs} ->
        {updated, consumed_item} = Behaviors.SubmissionTerminal.tick(key, building)

        if consumed_item, do: Statistics.record_consumption(key, consumed_item)

        new_updates = [{key, updated} | updates]

        new_subs =
          if consumed_item do
            [{key, building.owner_id, consumed_item} | subs]
          else
            subs
          end

        {new_updates, new_subs}
      end)

    # Phase 2e: Trade terminals tick (submit items to trades)
    trade_terminal_updates =
      Enum.map(trade_terminals, fn {key, building} ->
        {updated, _consumed} = Behaviors.TradeTerminal.tick(key, building)
        {key, updated}
      end)

    # Merge updates into the full building map
    all_buildings =
      merge_updates(
        buildings,
        miner_updates ++
          smelter_updates ++
          refinery_updates ++
          assembler_updates ++ terminal_updates ++ trade_terminal_updates
      )

    # Phase 2f: Conveyor Mk2/Mk3 internal buffer advancement
    all_buildings = advance_conveyor_buffers(all_buildings)

    # Phase 3: Push resolution — move items between buildings
    {final_buildings, movements} = resolve_pushes(all_buildings)

    # Phase 3b: Underground conduit teleportation
    {final_buildings, conduit_movements} = resolve_conduit_teleports(final_buildings)
    movements = movements ++ conduit_movements

    # Phase 4: Altered item duplication (5% chance to refill output after push)
    final_buildings = apply_duplication_effects(final_buildings, movements)

    # Batch write all modified building states to ETS
    write_changes(buildings, final_buildings)

    # Build per-face item state for broadcasting
    items_by_face = build_item_snapshot(final_buildings, movements)

    {tick, items_by_face, submissions}
  end

  defp gather_all_buildings do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        into: %{} do
      {key, building}
    end
  end

  defp classify(buildings) do
    Enum.reduce(buildings, {[], [], [], [], [], [], [], []}, fn {key, building},
                                                                {m, c, s, a, r, t, tt, o} ->
      case building.type do
        :miner ->
          {[{key, building} | m], c, s, a, r, t, tt, o}

        type when type in [:conveyor, :conveyor_mk2, :conveyor_mk3, :crossover] ->
          {m, [{key, building} | c], s, a, r, t, tt, o}

        :smelter ->
          {m, c, [{key, building} | s], a, r, t, tt, o}

        :assembler ->
          {m, c, s, [{key, building} | a], r, t, tt, o}

        :refinery ->
          {m, c, s, a, [{key, building} | r], t, tt, o}

        :submission_terminal ->
          {m, c, s, a, r, [{key, building} | t], tt, o}

        :trade_terminal ->
          {m, c, s, a, r, t, [{key, building} | tt], o}

        _ ->
          {m, c, s, a, r, t, tt, [{key, building} | o]}
      end
    end)
  end

  defp merge_updates(buildings, updates) do
    Enum.reduce(updates, buildings, fn {key, building}, acc ->
      Map.put(acc, key, building)
    end)
  end

  # Advance internal buffers for Mk2/Mk3 conveyors.
  # Shifts items from buffer slots toward the front (item) slot.
  defp advance_conveyor_buffers(buildings) do
    Enum.reduce(buildings, buildings, fn
      {key, %{type: :conveyor_mk2, state: %{item: nil, buffer: buf}} = b}, acc
      when not is_nil(buf) ->
        Map.put(acc, key, %{b | state: %{b.state | item: buf, buffer: nil}})

      {key, %{type: :conveyor_mk3, state: %{item: nil, buffer1: b1}} = b}, acc
      when not is_nil(b1) ->
        Map.put(acc, key, %{
          b
          | state: %{b.state | item: b1, buffer1: b.state.buffer2, buffer2: nil}
        })

      {key, %{type: :conveyor_mk3, state: %{buffer1: nil, buffer2: b2}} = b}, acc
      when not is_nil(b2) ->
        Map.put(acc, key, %{b | state: %{b.state | buffer1: b2, buffer2: nil}})

      _, acc ->
        acc
    end)
  end

  @doc """
  Resolve item movement. Returns `{final_buildings, movements}`.

  `movements` is a list of `{source_key, dest_key, item_type}`.
  """
  def resolve_pushes(buildings) do
    n = Application.get_env(:spheric, :subdivisions, 64)

    # Collect push requests from all buildings that have items to push
    push_requests =
      buildings
      |> Enum.flat_map(fn {key, building} ->
        get_push_requests(key, building, n)
      end)

    # Group by destination to detect conflicts
    by_dest = Enum.group_by(push_requests, fn {_src, dest, _item} -> dest end)

    # For each destination, accept at most one item
    accepted =
      Enum.flat_map(by_dest, fn {dest_key, requests} ->
        dest_building = Map.get(buildings, dest_key)

        case try_accept(dest_key, dest_building, requests, n) do
          nil -> []
          winner -> [winner]
        end
      end)

    # Record throughput for items moving through logistics buildings
    Enum.each(accepted, fn {src_key, _dest_key, item} ->
      src = Map.get(buildings, src_key)

      if src &&
           src.type in [
             :conveyor,
             :conveyor_mk2,
             :conveyor_mk3,
             :splitter,
             :merger,
             :balancer,
             :crossover
           ] do
        Statistics.record_throughput(src_key, item)
      end
    end)

    # Apply accepted pushes
    final = apply_pushes(buildings, accepted)
    {final, accepted}
  end

  # --- Push request generation ---

  # Wrapper that returns a list of push requests. Most buildings produce 0 or 1.
  # Crossover produces 0-2 (one per axis).
  defp get_push_requests(key, %{type: :crossover, state: state}, n) do
    h =
      if state.horizontal != nil and state.h_dir != nil do
        case TileNeighbors.neighbor(key, state.h_dir, n) do
          {:ok, dest_key} -> {key, dest_key, state.horizontal}
          :boundary -> nil
        end
      end

    v =
      if state.vertical != nil and state.v_dir != nil do
        case TileNeighbors.neighbor(key, state.v_dir, n) do
          {:ok, dest_key} -> {key, dest_key, state.vertical}
          :boundary -> nil
        end
      end

    Enum.reject([h, v], &is_nil/1)
  end

  defp get_push_requests(key, building, n) do
    case get_push_request(key, building, n) do
      nil -> []
      request -> [request]
    end
  end

  defp get_push_request(key, %{type: :conveyor, orientation: dir, state: %{item: item}}, n)
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(key, %{type: :conveyor_mk2, orientation: dir, state: %{item: item}}, n)
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  defp get_push_request(key, %{type: :conveyor_mk3, orientation: dir, state: %{item: item}}, n)
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

  # Balancer: smart splitter that checks downstream fullness
  defp get_push_request(
         key,
         %{type: :balancer, orientation: dir, state: %{item: item, last_output: last}},
         n
       )
       when not is_nil(item) do
    {left, right} = Behaviors.Balancer.output_directions(dir)

    left_key =
      case TileNeighbors.neighbor(key, left, n) do
        {:ok, k} -> k
        :boundary -> nil
      end

    right_key =
      case TileNeighbors.neighbor(key, right, n) do
        {:ok, k} -> k
        :boundary -> nil
      end

    # Check downstream fullness — prefer the less-full side
    left_full = left_key == nil or downstream_full?(left_key)
    right_full = right_key == nil or downstream_full?(right_key)

    output_dir =
      cond do
        left_full and right_full -> nil
        left_full -> right
        right_full -> left
        # Both available: alternate
        last == :left -> right
        true -> left
      end

    if output_dir do
      case TileNeighbors.neighbor(key, output_dir, n) do
        {:ok, dest_key} -> {key, dest_key, item}
        :boundary -> nil
      end
    else
      nil
    end
  end

  # Storage container: pushes items from its stock to the front
  defp get_push_request(
         key,
         %{
           type: :storage_container,
           orientation: dir,
           state: %{item_type: item_type, count: count}
         },
         n
       )
       when not is_nil(item_type) and count > 0 do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item_type}
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

  defp get_push_request(
         key,
         %{type: :assembler, orientation: dir, state: %{output_buffer: item}},
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
         %{type: :refinery, orientation: dir, state: %{output_buffer: item}},
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
         %{type: :defense_turret, orientation: dir, state: %{output_buffer: item}},
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
         %{type: :trade_terminal, orientation: dir, state: %{output_buffer: item}},
         n
       )
       when not is_nil(item) do
    case TileNeighbors.neighbor(key, dir, n) do
      {:ok, dest_key} -> {key, dest_key, item}
      :boundary -> nil
    end
  end

  # Underground conduit: push item from linked conduit's output
  # (handled separately in resolve_conduit_teleports)

  defp get_push_request(_key, _building, _n), do: nil

  # Check if a building's input slot is full (for balancer logic)
  defp downstream_full?(key) do
    case WorldStore.get_building(key) do
      nil ->
        true

      %{type: :conveyor, state: %{item: item}} ->
        item != nil

      %{type: :conveyor_mk2, state: %{item: item, buffer: buf}} ->
        item != nil and buf != nil

      %{type: :conveyor_mk3, state: %{item: item, buffer1: b1, buffer2: b2}} ->
        item != nil and b1 != nil and b2 != nil

      %{type: :smelter, state: %{input_buffer: buf}} ->
        buf != nil

      %{type: :refinery, state: %{input_buffer: buf}} ->
        buf != nil

      %{type: :splitter, state: %{item: item}} ->
        item != nil

      %{type: :merger, state: %{item: item}} ->
        item != nil

      %{type: :balancer, state: %{item: item}} ->
        item != nil

      %{type: :crossover, state: state} ->
        state.horizontal != nil and state.vertical != nil

      %{type: :storage_container, state: state} ->
        state.count >= state.capacity

      _ ->
        false
    end
  end

  # --- Acceptance logic ---

  # Try to accept an item at the destination building
  defp try_accept(_key, nil, _requests, _n), do: nil

  defp try_accept(_key, %{type: :conveyor, state: %{item: nil}}, [winner | _], _n), do: winner

  # Conveyor Mk2: accept if any slot available
  defp try_accept(_key, %{type: :conveyor_mk2, state: state}, [winner | _], _n) do
    cond do
      state.item == nil -> winner
      state.buffer == nil -> winner
      true -> nil
    end
  end

  # Conveyor Mk3: accept if any slot available
  defp try_accept(_key, %{type: :conveyor_mk3, state: state}, [winner | _], _n) do
    cond do
      state.item == nil -> winner
      state.buffer1 == nil -> winner
      state.buffer2 == nil -> winner
      true -> nil
    end
  end

  defp try_accept(_key, %{type: :smelter, state: %{input_buffer: nil}}, [winner | _], _n),
    do: winner

  defp try_accept(_key, %{type: :refinery, state: %{input_buffer: nil}}, [winner | _], _n),
    do: winner

  # Storage container: accepts items from rear, if type matches and not full
  defp try_accept(
         dest_key,
         %{type: :storage_container, orientation: dir, state: state},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.StorageContainer.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Underground conduit: accepts items from the rear
  defp try_accept(
         dest_key,
         %{type: :underground_conduit, orientation: dir, state: %{item: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)
    accept_from_direction(dest_key, rear_dir, requests, n)
  end

  # Submission terminal: accepts any item into input_buffer from the rear
  defp try_accept(
         dest_key,
         %{type: :submission_terminal, orientation: dir, state: %{input_buffer: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)
    accept_from_direction(dest_key, rear_dir, requests, n)
  end

  # Assembler: accepts from rear, routes item to correct input slot via dual-input logic
  defp try_accept(dest_key, %{type: :assembler, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.Assembler.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Splitter: only accepts from the rear (opposite of orientation)
  defp try_accept(
         dest_key,
         %{type: :splitter, orientation: dir, state: %{item: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)
    accept_from_direction(dest_key, rear_dir, requests, n)
  end

  # Balancer: only accepts from the rear (opposite of orientation)
  defp try_accept(
         dest_key,
         %{type: :balancer, orientation: dir, state: %{item: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)
    accept_from_direction(dest_key, rear_dir, requests, n)
  end

  # Crossover: accepts from any direction into the correct axis slot
  defp try_accept(dest_key, %{type: :crossover, state: state}, requests, n) do
    # Try each of the 4 directions to find a valid source
    Enum.find_value(0..3, fn dir ->
      slot = if dir in [0, 2], do: :horizontal, else: :vertical
      slot_val = Map.get(state, slot)

      if slot_val == nil do
        case TileNeighbors.neighbor(dest_key, dir, n) do
          {:ok, valid_src} ->
            Enum.find(requests, fn {src, _dest, _item} -> src == valid_src end)

          :boundary ->
            nil
        end
      end
    end)
  end

  # Merger: accepts from the two side inputs (left and right of orientation)
  defp try_accept(dest_key, %{type: :merger, orientation: dir, state: %{item: nil}}, requests, n) do
    left_dir = rem(dir + 3, 4)
    right_dir = rem(dir + 1, 4)

    accept_from_directions(dest_key, [left_dir, right_dir], requests, n)
  end

  # Trade terminal: accepts any item into input_buffer from the rear
  defp try_accept(
         dest_key,
         %{type: :trade_terminal, orientation: dir, state: %{input_buffer: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)
    accept_from_direction(dest_key, rear_dir, requests, n)
  end

  defp try_accept(_key, _building, _requests, _n), do: nil

  # Accept the first request whose source is the neighbor in the given direction
  defp accept_from_direction(dest_key, direction, requests, n) do
    case TileNeighbors.neighbor(dest_key, direction, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, _item} -> src == valid_src end)

      :boundary ->
        nil
    end
  end

  # Accept the first request whose source is a neighbor in any of the given directions
  defp accept_from_directions(dest_key, directions, requests, n) do
    valid_sources =
      for dir <- directions,
          {:ok, src} <- [TileNeighbors.neighbor(dest_key, dir, n)],
          into: MapSet.new(),
          do: src

    Enum.find(requests, fn {src, _dest, _item} -> MapSet.member?(valid_sources, src) end)
  end

  # Determine which crossover slot a source maps to, and the exit direction.
  # Entry from direction D means exit = (D + 2) rem 4 (passthrough).
  # Directions 0/2 = horizontal axis, 1/3 = vertical axis.
  defp crossover_slot_for_source(dest_key, src_key, n) do
    entry_dir =
      Enum.find(0..3, fn dir ->
        case TileNeighbors.neighbor(dest_key, dir, n) do
          {:ok, ^src_key} -> true
          _ -> false
        end
      end)

    exit_dir = rem(entry_dir + 2, 4)
    slot = if entry_dir in [0, 2], do: :horizontal, else: :vertical
    {slot, exit_dir}
  end

  defp apply_pushes(buildings, accepted) do
    Enum.reduce(accepted, buildings, fn {src_key, dest_key, item}, acc ->
      # Clear source output
      acc =
        Map.update!(acc, src_key, fn b ->
          case b.type do
            :conveyor ->
              %{b | state: %{b.state | item: nil}}

            :conveyor_mk2 ->
              %{b | state: %{b.state | item: nil}}

            :conveyor_mk3 ->
              %{b | state: %{b.state | item: nil}}

            :miner ->
              %{b | state: %{b.state | output_buffer: nil}}

            :smelter ->
              %{b | state: %{b.state | output_buffer: nil}}

            :assembler ->
              %{b | state: %{b.state | output_buffer: nil}}

            :refinery ->
              %{b | state: %{b.state | output_buffer: nil}}

            :defense_turret ->
              %{b | state: %{b.state | output_buffer: nil}}

            :trade_terminal ->
              %{b | state: %{b.state | output_buffer: nil}}

            :splitter ->
              next = if b.state.next_output == :left, do: :right, else: :left
              %{b | state: %{b.state | item: nil, next_output: next}}

            :balancer ->
              # Track which side was last used
              dir = b.orientation
              {left, _right} = Behaviors.Balancer.output_directions(dir)
              n = Application.get_env(:spheric, :subdivisions, 64)

              dest_dir =
                case TileNeighbors.neighbor(src_key, left, n) do
                  {:ok, ^dest_key} -> :left
                  _ -> :right
                end

              %{b | state: %{b.state | item: nil, last_output: dest_dir}}

            :merger ->
              %{b | state: %{b.state | item: nil}}

            :crossover ->
              # Determine which slot pushed to this dest by checking h_dir
              sub_n = Application.get_env(:spheric, :subdivisions, 64)

              h_dest =
                if b.state.h_dir,
                  do: TileNeighbors.neighbor(src_key, b.state.h_dir, sub_n)

              if h_dest == {:ok, dest_key} do
                %{b | state: %{b.state | horizontal: nil, h_dir: nil}}
              else
                %{b | state: %{b.state | vertical: nil, v_dir: nil}}
              end

            :storage_container ->
              new_count = max(0, b.state.count - 1)
              new_type = if new_count == 0, do: nil, else: b.state.item_type
              %{b | state: %{b.state | count: new_count, item_type: new_type}}

            _ ->
              b
          end
        end)

      # Set destination input
      Map.update!(acc, dest_key, fn b ->
        case b.type do
          :conveyor ->
            %{b | state: %{b.state | item: item}}

          :conveyor_mk2 ->
            cond do
              b.state.item == nil -> %{b | state: %{b.state | item: item}}
              b.state.buffer == nil -> %{b | state: %{b.state | buffer: item}}
              true -> b
            end

          :conveyor_mk3 ->
            cond do
              b.state.item == nil -> %{b | state: %{b.state | item: item}}
              b.state.buffer1 == nil -> %{b | state: %{b.state | buffer1: item}}
              b.state.buffer2 == nil -> %{b | state: %{b.state | buffer2: item}}
              true -> b
            end

          :smelter ->
            %{b | state: %{b.state | input_buffer: item}}

          :refinery ->
            %{b | state: %{b.state | input_buffer: item}}

          :assembler ->
            case Behaviors.Assembler.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :crossover ->
            sub_n = Application.get_env(:spheric, :subdivisions, 64)

            {slot, exit_dir} =
              crossover_slot_for_source(dest_key, src_key, sub_n)

            case slot do
              :horizontal ->
                %{b | state: %{b.state | horizontal: item, h_dir: exit_dir}}

              :vertical ->
                %{b | state: %{b.state | vertical: item, v_dir: exit_dir}}
            end

          :splitter ->
            %{b | state: %{b.state | item: item}}

          :balancer ->
            %{b | state: %{b.state | item: item}}

          :merger ->
            %{b | state: %{b.state | item: item}}

          :storage_container ->
            case Behaviors.StorageContainer.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :underground_conduit ->
            %{b | state: %{b.state | item: item}}

          :submission_terminal ->
            %{b | state: %{b.state | input_buffer: item}}

          :trade_terminal ->
            %{b | state: %{b.state | input_buffer: item}}

          _ ->
            b
        end
      end)
    end)
  end

  # Underground conduit teleportation: after normal push resolution,
  # check conduits holding items and teleport them to their linked partner.
  defp resolve_conduit_teleports(buildings) do
    conduit_movements =
      buildings
      |> Enum.filter(fn {_key, b} ->
        b.type == :underground_conduit and b.state[:item] != nil and b.state[:linked_to] != nil
      end)
      |> Enum.flat_map(fn {src_key, b} ->
        dest_key = b.state.linked_to
        dest = Map.get(buildings, dest_key)

        if dest && dest.type == :underground_conduit && dest.state[:item] == nil do
          [{src_key, dest_key, b.state.item}]
        else
          []
        end
      end)

    final =
      Enum.reduce(conduit_movements, buildings, fn {src_key, dest_key, item}, acc ->
        acc =
          Map.update!(acc, src_key, fn b ->
            %{b | state: %{b.state | item: nil}}
          end)

        Map.update!(acc, dest_key, fn b ->
          %{b | state: %{b.state | item: item}}
        end)
      end)

    {final, conduit_movements}
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

  # Crossover: up to 2 items (one per axis)
  defp items_from_building({face, row, col}, %{type: :crossover, state: state}, sources) do
    from = Map.get(sources, {face, row, col})

    h =
      if state.horizontal do
        [
          %{
            face: face,
            row: row,
            col: col,
            item: state.horizontal,
            from_face: if(from, do: elem(from, 0)),
            from_row: if(from, do: elem(from, 1)),
            from_col: if(from, do: elem(from, 2))
          }
        ]
      else
        []
      end

    v =
      if state.vertical do
        [
          %{
            face: face,
            row: row,
            col: col,
            item: state.vertical,
            from_face: nil,
            from_row: nil,
            from_col: nil
          }
        ]
      else
        []
      end

    h ++ v
  end

  defp items_from_building({face, row, col}, %{type: type, state: %{item: item}}, sources)
       when type in [
              :conveyor,
              :conveyor_mk2,
              :conveyor_mk3,
              :splitter,
              :merger,
              :balancer,
              :underground_conduit
            ] and
              not is_nil(item) do
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

  defp items_from_building({face, row, col}, %{type: type, state: %{output_buffer: item}}, _)
       when type in [:miner, :smelter, :assembler, :refinery, :defense_turret, :trade_terminal] and
              not is_nil(item) do
    [%{face: face, row: row, col: col, item: item, from_face: nil, from_row: nil, from_col: nil}]
  end

  defp items_from_building(_key, _building, _sources), do: []

  # Altered item: duplication effect.
  # For buildings with :duplication that just pushed their output, there's a 5%
  # chance the output buffer gets refilled with the same item (free duplication).
  defp apply_duplication_effects(buildings, movements) do
    # Find source buildings that pushed items and have duplication effect
    Enum.reduce(movements, buildings, fn {src_key, _dest_key, item}, acc ->
      building = Map.get(acc, src_key)

      if building && building.state[:altered_effect] == :duplication &&
           building.state[:output_buffer] == nil do
        if :rand.uniform(100) <= 5 do
          Map.put(acc, src_key, %{
            building
            | state: Map.put(building.state, :output_buffer, item)
          })
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # Record production/consumption stats by comparing building state before and after tick.
  defp record_production_stats(key, old_building, new_building) do
    old_state = old_building.state
    new_state = new_building.state

    # Detect production: output_buffer went from nil to a value
    if old_state[:output_buffer] == nil and new_state[:output_buffer] != nil do
      Statistics.record_production(key, new_state.output_buffer)
    end

    # Detect consumption for single-input buildings (smelter, refinery)
    if old_state[:input_buffer] != nil and new_state[:input_buffer] == nil and
         new_state[:output_buffer] != nil do
      Statistics.record_consumption(key, old_state.input_buffer)
    end

    # Detect consumption for dual-input buildings (assembler)
    if old_state[:input_a] != nil and old_state[:input_b] != nil and
         new_state[:input_a] == nil and new_state[:input_b] == nil and
         new_state[:output_buffer] != nil do
      Statistics.record_consumption(key, old_state.input_a)
      Statistics.record_consumption(key, old_state.input_b)
    end
  end

  # Apply creature boost and altered item effects to a building's tick rate.
  # Temporarily adjusts the rate in the building state so the behavior
  # module uses the boosted rate for its progress check.
  defp apply_creature_boost(key, building) do
    case building.state do
      %{rate: base_rate} ->
        boosted = Creatures.boosted_rate(key, base_rate)

        # Altered item: overclock halves the effective rate
        boosted =
          if building.state[:altered_effect] == :overclock do
            max(1, div(boosted, 2))
          else
            boosted
          end

        # Object of Power: production_surge gives 10% speed boost
        boosted =
          if building[:owner_id] &&
               ObjectsOfPower.player_has?(building.owner_id, :production_surge) do
            max(1, round(boosted * 0.9))
          else
            boosted
          end

        # Shift Cycle: biome-based rate modifier for miners
        boosted =
          if building.type == :miner do
            tile = WorldStore.get_tile(key)
            biome = if tile, do: tile.terrain, else: :grassland
            ShiftCycle.apply_rate_modifier(boosted, biome)
          else
            boosted
          end

        if boosted != base_rate do
          %{building | state: %{building.state | rate: boosted}}
        else
          building
        end

      _ ->
        building
    end
  end
end
