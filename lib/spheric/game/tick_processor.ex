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

  alias Spheric.Game.{
    WorldStore,
    Behaviors,
    Creatures,
    ObjectsOfPower,
    Statistics,
    ShiftCycle,
    ConstructionCosts,
    GroundItems,
    Power
  }

  alias Spheric.Geometry.TileNeighbors

  require Logger

  @doc """
  Process one tick. Returns `{tick, items_by_face}`.
  """
  def process_tick(tick) do
    original_buildings = gather_all_buildings()

    # Phase 0: Construction delivery — pull from ground items into construction sites
    {buildings, newly_completed} = process_construction_delivery(original_buildings)

    # Phase 0b: Power resolution (every 5 ticks)
    if rem(tick, 5) == 0, do: Power.resolve()

    # Filter out incomplete construction sites for production phases
    active_buildings =
      Map.filter(buildings, fn {_key, b} ->
        not (b.state[:construction] != nil and b.state.construction.complete == false)
      end)

    classified = classify(active_buildings)

    # Phase 1: Miners tick (with creature boost + power)
    miner_updates =
      Enum.map(classified.miners, fn {key, building} ->
        updated = Behaviors.Miner.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2: Smelters tick
    smelter_updates =
      Enum.map(classified.smelters, fn {key, building} ->
        updated = Behaviors.Smelter.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2b: Refineries tick
    refinery_updates =
      Enum.map(classified.refineries, fn {key, building} ->
        updated = Behaviors.Refinery.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2c: Assemblers tick
    assembler_updates =
      Enum.map(classified.assemblers, fn {key, building} ->
        updated = Behaviors.Assembler.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2d: Advanced smelters tick
    adv_smelter_updates =
      Enum.map(classified.advanced_smelters, fn {key, building} ->
        updated = Behaviors.AdvancedSmelter.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2e: Advanced assemblers tick
    adv_assembler_updates =
      Enum.map(classified.advanced_assemblers, fn {key, building} ->
        updated = Behaviors.AdvancedAssembler.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2f: Fabrication plants tick
    fab_plant_updates =
      Enum.map(classified.fabrication_plants, fn {key, building} ->
        updated = Behaviors.FabricationPlant.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2g: Particle colliders tick
    collider_updates =
      Enum.map(classified.particle_colliders, fn {key, building} ->
        updated = Behaviors.ParticleCollider.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2h: Nuclear refineries tick
    nuclear_updates =
      Enum.map(classified.nuclear_refineries, fn {key, building} ->
        updated = Behaviors.NuclearRefinery.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2i: Paranatural synthesizers tick
    synthesizer_updates =
      Enum.map(classified.paranatural_synthesizers, fn {key, building} ->
        updated = Behaviors.ParanaturalSynthesizer.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2j: Board interfaces tick
    board_updates =
      Enum.map(classified.board_interfaces, fn {key, building} ->
        updated = Behaviors.BoardInterface.tick(key, apply_creature_boost(key, building))
        record_production_stats(key, building, updated)
        {key, updated}
      end)

    # Phase 2k: Bio generators tick
    bio_gen_updates =
      Enum.map(classified.bio_generators, fn {key, building} ->
        updated = Behaviors.BioGenerator.tick(key, apply_creature_boost(key, building))
        {key, updated}
      end)

    # Phase 2k2: Shadow panels tick
    shadow_panel_updates =
      Enum.map(classified.shadow_panels, fn {key, building} ->
        updated = Behaviors.ShadowPanel.tick(key, building)
        {key, updated}
      end)

    # Phase 2l: Gathering posts tick
    gathering_updates =
      Enum.map(classified.gathering_posts, fn {key, building} ->
        updated = Behaviors.GatheringPost.tick(key, building)
        {key, updated}
      end)

    # Phase 2m: Essence extractors tick
    essence_updates =
      Enum.map(classified.essence_extractors, fn {key, building} ->
        updated = Behaviors.EssenceExtractor.tick(key, building)
        {key, updated}
      end)

    # Phase 2n: Submission terminals tick (consume items, report submissions)
    {terminal_updates, submissions} =
      Enum.reduce(classified.terminals, {[], []}, fn {key, building}, {updates, subs} ->
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

    # Phase 2o: Trade terminals tick
    trade_terminal_updates =
      Enum.map(classified.trade_terminals, fn {key, building} ->
        {updated, _consumed} = Behaviors.TradeTerminal.tick(key, building)
        {key, updated}
      end)

    # Merge all updates into the full building map (includes inactive construction sites)
    all_updates =
      miner_updates ++
        smelter_updates ++
        refinery_updates ++
        assembler_updates ++
        adv_smelter_updates ++
        adv_assembler_updates ++
        fab_plant_updates ++
        collider_updates ++
        nuclear_updates ++
        synthesizer_updates ++
        board_updates ++
        bio_gen_updates ++
        shadow_panel_updates ++
        gathering_updates ++
        essence_updates ++
        terminal_updates ++ trade_terminal_updates

    all_buildings = merge_updates(buildings, all_updates)

    # Phase 2p: Conveyor Mk2/Mk3 internal buffer advancement
    all_buildings = advance_conveyor_buffers(all_buildings)

    # Phase 3: Push resolution — move items between buildings
    {final_buildings, movements} = resolve_pushes(all_buildings)

    # Phase 3b: Underground conduit teleportation
    {final_buildings, conduit_movements} = resolve_conduit_teleports(final_buildings)
    movements = movements ++ conduit_movements

    # Phase 4: Altered item duplication (5% chance to refill output after push)
    final_buildings = apply_duplication_effects(final_buildings, movements)

    # Phase 4b: Efficiency boost — chance to not consume input
    final_buildings = apply_efficiency_effects(final_buildings)

    # Phase 4c: Output boost — chance to double output
    final_buildings = apply_output_effects(final_buildings, movements)

    # Batch write all modified building states to ETS
    write_changes(original_buildings, final_buildings)

    # Detect construction completions from push delivery (not caught by ground delivery)
    completed_set = MapSet.new(newly_completed)

    push_completed =
      Enum.flat_map(final_buildings, fn {key, building} ->
        if not MapSet.member?(completed_set, key) and
             building.state[:construction] != nil and
             building.state.construction.complete == true do
          orig = Map.get(original_buildings, key)

          if orig != nil and orig.state[:construction] != nil and
               orig.state.construction.complete == false do
            [key]
          else
            []
          end
        else
          []
        end
      end)

    newly_completed = newly_completed ++ push_completed

    # Build per-face item state for broadcasting
    items_by_face = build_item_snapshot(final_buildings, movements)

    {tick, items_by_face, submissions, newly_completed}
  end

  defp gather_all_buildings do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        into: %{} do
      {key, building}
    end
  end

  defp classify(buildings) do
    acc = %{
      miners: [],
      conveyors: [],
      smelters: [],
      assemblers: [],
      refineries: [],
      terminals: [],
      trade_terminals: [],
      advanced_smelters: [],
      advanced_assemblers: [],
      fabrication_plants: [],
      particle_colliders: [],
      nuclear_refineries: [],
      paranatural_synthesizers: [],
      board_interfaces: [],
      bio_generators: [],
      shadow_panels: [],
      gathering_posts: [],
      essence_extractors: [],
      others: []
    }

    Enum.reduce(buildings, acc, fn {key, building}, acc ->
      pair = {key, building}

      case building.type do
        :miner -> %{acc | miners: [pair | acc.miners]}
        type when type in [:conveyor, :conveyor_mk2, :conveyor_mk3, :crossover] -> %{acc | conveyors: [pair | acc.conveyors]}
        :smelter -> %{acc | smelters: [pair | acc.smelters]}
        :assembler -> %{acc | assemblers: [pair | acc.assemblers]}
        :refinery -> %{acc | refineries: [pair | acc.refineries]}
        :submission_terminal -> %{acc | terminals: [pair | acc.terminals]}
        :trade_terminal -> %{acc | trade_terminals: [pair | acc.trade_terminals]}
        :advanced_smelter -> %{acc | advanced_smelters: [pair | acc.advanced_smelters]}
        :advanced_assembler -> %{acc | advanced_assemblers: [pair | acc.advanced_assemblers]}
        :fabrication_plant -> %{acc | fabrication_plants: [pair | acc.fabrication_plants]}
        :particle_collider -> %{acc | particle_colliders: [pair | acc.particle_colliders]}
        :nuclear_refinery -> %{acc | nuclear_refineries: [pair | acc.nuclear_refineries]}
        :paranatural_synthesizer -> %{acc | paranatural_synthesizers: [pair | acc.paranatural_synthesizers]}
        :board_interface -> %{acc | board_interfaces: [pair | acc.board_interfaces]}
        :bio_generator -> %{acc | bio_generators: [pair | acc.bio_generators]}
        :shadow_panel -> %{acc | shadow_panels: [pair | acc.shadow_panels]}
        :lamp -> acc
        :gathering_post -> %{acc | gathering_posts: [pair | acc.gathering_posts]}
        :essence_extractor -> %{acc | essence_extractors: [pair | acc.essence_extractors]}
        _ -> %{acc | others: [pair | acc.others]}
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

  # All other buildings with output_buffer + orientation push forward
  defp get_push_request(
         key,
         %{type: type, orientation: dir, state: %{output_buffer: item}},
         n
       )
       when type in [
              :advanced_smelter,
              :advanced_assembler,
              :fabrication_plant,
              :particle_collider,
              :nuclear_refinery,
              :paranatural_synthesizer,
              :board_interface,
              :gathering_post,
              :essence_extractor
            ] and not is_nil(item) do
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

      %{type: :smelter, state: state} ->
        Behaviors.Smelter.full?(state)

      %{type: :refinery, state: state} ->
        Behaviors.Refinery.full?(state)

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

      %{type: :assembler, state: state} ->
        Behaviors.Assembler.full?(state)

      %{type: :advanced_smelter, state: state} ->
        Behaviors.AdvancedSmelter.full?(state)

      %{type: :advanced_assembler, state: state} ->
        Behaviors.AdvancedAssembler.full?(state)

      %{type: :fabrication_plant, state: state} ->
        Behaviors.FabricationPlant.full?(state)

      %{type: :particle_collider, state: state} ->
        Behaviors.ParticleCollider.full?(state)

      %{type: :nuclear_refinery, state: state} ->
        Behaviors.NuclearRefinery.full?(state)

      %{type: :paranatural_synthesizer, state: state} ->
        Behaviors.ParanaturalSynthesizer.full?(state)

      %{type: :board_interface, state: state} ->
        Behaviors.BoardInterface.full?(state)

      %{type: :bio_generator, state: %{input_buffer: buf}} ->
        buf != nil

      %{type: :submission_terminal, state: %{input_buffer: buf}} ->
        buf != nil

      _ ->
        false
    end
  end

  # --- Acceptance logic ---

  # Try to accept an item at the destination building
  defp try_accept(_key, nil, _requests, _n), do: nil

  # Construction sites: accept needed items from any adjacent building
  defp try_accept(
         _dest_key,
         %{state: %{construction: %{complete: false} = constr}} = _building,
         requests,
         _n
       ) do
    Enum.find(requests, fn {_src, _dest, item} ->
      ConstructionCosts.needs_item?(constr, item)
    end)
  end

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

  defp try_accept(dest_key, %{type: :smelter, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.Smelter.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  defp try_accept(dest_key, %{type: :refinery, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.Refinery.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

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

  # Advanced smelter: accepts from rear into input_buffer
  defp try_accept(dest_key, %{type: :advanced_smelter, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.AdvancedSmelter.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Advanced assembler: dual-input, routes item to correct slot
  defp try_accept(dest_key, %{type: :advanced_assembler, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.AdvancedAssembler.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Fabrication plant: triple-input, routes item to correct slot
  defp try_accept(dest_key, %{type: :fabrication_plant, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.FabricationPlant.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Particle collider: dual-input
  defp try_accept(dest_key, %{type: :particle_collider, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.ParticleCollider.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Nuclear refinery: single-input from rear
  defp try_accept(dest_key, %{type: :nuclear_refinery, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.NuclearRefinery.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Paranatural synthesizer: triple-input
  defp try_accept(dest_key, %{type: :paranatural_synthesizer, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.ParanaturalSynthesizer.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Board interface: triple-input
  defp try_accept(dest_key, %{type: :board_interface, orientation: dir, state: state}, requests, n) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and Behaviors.BoardInterface.try_accept_item(state, item) != nil
        end)

      :boundary ->
        nil
    end
  end

  # Bio generator: accepts fuel from rear into input_buffer
  defp try_accept(
         dest_key,
         %{type: :bio_generator, orientation: dir, state: %{input_buffer: nil}},
         requests,
         n
       ) do
    rear_dir = rem(dir + 2, 4)

    case TileNeighbors.neighbor(dest_key, rear_dir, n) do
      {:ok, valid_src} ->
        Enum.find(requests, fn {src, _dest, item} ->
          src == valid_src and item in [:biofuel, :refined_fuel]
        end)

      :boundary ->
        nil
    end
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

            type
            when type in [
                   :advanced_smelter,
                   :advanced_assembler,
                   :fabrication_plant,
                   :particle_collider,
                   :nuclear_refinery,
                   :paranatural_synthesizer,
                   :board_interface,
                   :gathering_post,
                   :essence_extractor
                 ] ->
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
        # Construction sites consume items as construction materials, not normal input
        if b.state[:construction] != nil and b.state.construction.complete == false do
          case ConstructionCosts.deliver_item(b.state.construction, item) do
            nil -> b
            new_constr -> %{b | state: %{b.state | construction: new_constr}}
          end
        else
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
            case Behaviors.Smelter.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :refinery ->
            case Behaviors.Refinery.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

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

          :advanced_smelter ->
            case Behaviors.AdvancedSmelter.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :advanced_assembler ->
            case Behaviors.AdvancedAssembler.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :fabrication_plant ->
            case Behaviors.FabricationPlant.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :particle_collider ->
            case Behaviors.ParticleCollider.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :nuclear_refinery ->
            case Behaviors.NuclearRefinery.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :paranatural_synthesizer ->
            case Behaviors.ParanaturalSynthesizer.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :board_interface ->
            case Behaviors.BoardInterface.try_accept_item(b.state, item) do
              nil -> b
              new_state -> %{b | state: new_state}
            end

          :bio_generator ->
            if item in [:biofuel, :refined_fuel] do
              %{b | state: %{b.state | input_buffer: item}}
            else
              b
            end

          _ ->
            b
        end
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

    building_items =
      Enum.flat_map(buildings, fn {key, building} ->
        items_from_building(key, building, movement_sources)
      end)

    # Include ground items so they render on the sphere
    ground_items =
      GroundItems.all()
      |> Enum.flat_map(fn {{face, row, col}, items_map} ->
        Enum.map(items_map, fn {item_type, _count} ->
          %{face: face, row: row, col: col, item: item_type, from_face: nil, from_row: nil, from_col: nil}
        end)
      end)

    (building_items ++ ground_items)
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
       when type in [
              :miner,
              :smelter,
              :assembler,
              :refinery,
              :defense_turret,
              :trade_terminal,
              :advanced_smelter,
              :advanced_assembler,
              :fabrication_plant,
              :particle_collider,
              :nuclear_refinery,
              :paranatural_synthesizer,
              :board_interface,
              :gathering_post,
              :essence_extractor
            ] and
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
           building.state[:output_buffer] == nil &&
           (building.state[:output_remaining] || 0) == 0 do
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

    # Detect consumption for single-input buildings (smelter, refinery, etc.)
    # Inputs are consumed when input_buffer goes from non-nil to nil
    if old_state[:input_buffer] != nil and new_state[:input_buffer] == nil and
         new_state[:output_buffer] != nil do
      old_count = old_state[:input_count] || 1
      for _ <- 1..old_count, do: Statistics.record_consumption(key, old_state.input_buffer)
    end

    # Detect consumption for dual-input buildings (assembler, etc.)
    if old_state[:input_a] != nil and old_state[:input_b] != nil and
         new_state[:input_a] == nil and new_state[:input_b] == nil and
         new_state[:output_buffer] != nil do
      old_a_count = old_state[:input_a_count] || 1
      old_b_count = old_state[:input_b_count] || 1
      for _ <- 1..old_a_count, do: Statistics.record_consumption(key, old_state.input_a)
      for _ <- 1..old_b_count, do: Statistics.record_consumption(key, old_state.input_b)

      # Triple-input: also consume input_c
      if old_state[:input_c] != nil and new_state[:input_c] == nil do
        old_c_count = old_state[:input_c_count] || 1
        for _ <- 1..old_c_count, do: Statistics.record_consumption(key, old_state.input_c)
      end
    end
  end

  # Process construction delivery: pull items from nearby ground items and buildings
  # Returns {updated_buildings, newly_completed_keys}
  defp process_construction_delivery(buildings) do
    {updated, completed} =
      Enum.reduce(buildings, {buildings, []}, fn {key, building}, {acc, completed_keys} ->
        case building.state do
          %{construction: %{complete: false} = constr} ->
            needed =
              Enum.flat_map(constr.required, fn {item, qty} ->
                delivered = Map.get(constr.delivered, item, 0)
                if delivered < qty, do: [item], else: []
              end)

            if needed == [] do
              new_constr = %{constr | complete: true}
              new_acc = Map.put(acc, key, %{building | state: %{building.state | construction: new_constr}})
              {new_acc, [key | completed_keys]}
            else
              # Try to pull from ground items first
              nearby_ground = GroundItems.items_near(key, 3)

              {new_constr, remaining_needed} =
                Enum.reduce(needed, {constr, []}, fn item, {c, still_needed} ->
                  ground_count =
                    Enum.reduce(nearby_ground, 0, fn {_tile_key, items}, sum ->
                      sum + Map.get(items, item, 0)
                    end)

                  if ground_count > 0 do
                    {taken_key, _} =
                      Enum.find(nearby_ground, fn {_tile_key, items} ->
                        Map.get(items, item, 0) > 0
                      end)

                    GroundItems.take(taken_key, item)
                    {ConstructionCosts.deliver_item(c, item), still_needed}
                  else
                    {c, [item | still_needed]}
                  end
                end)

              # Then try to pull from nearby buildings holding items (radius 3)
              {new_constr, acc} =
                Enum.reduce(remaining_needed, {new_constr, acc}, fn item, {c, b_acc} ->
                  case find_nearby_building_with_item(key, item, b_acc) do
                    nil ->
                      {c, b_acc}

                    {donor_key, updated_donor} ->
                      b_acc = Map.put(b_acc, donor_key, updated_donor)
                      {ConstructionCosts.deliver_item(c, item), b_acc}
                  end
                end)

              if ConstructionCosts.construction_complete?(new_constr) do
                new_constr = %{new_constr | complete: true}
                new_acc = Map.put(acc, key, %{building | state: %{building.state | construction: new_constr}})
                {new_acc, [key | completed_keys]}
              else
                new_acc = Map.put(acc, key, %{building | state: %{building.state | construction: new_constr}})
                {new_acc, completed_keys}
              end
            end

          _ ->
            {acc, completed_keys}
        end
      end)

    {updated, completed}
  end

  # Find a nearby building (radius 3, same face) holding the needed item and return
  # {donor_key, updated_donor_building} with the item removed, or nil.
  defp find_nearby_building_with_item({face, row, col}, item, buildings) do
    Enum.find_value(buildings, fn {{bf, br, bc} = bkey, b} ->
      under_construction =
        b.state[:construction] != nil and b.state.construction.complete == false

      if bf == face and bkey != {face, row, col} and
           abs(br - row) <= 3 and abs(bc - col) <= 3 and
           not under_construction do
        take_item_from_building(bkey, b, item)
      end
    end)
  end

  # Try to take a specific item from a building's held slots.
  # Returns {key, updated_building} or nil.
  defp take_item_from_building(key, %{state: %{item: held}} = b, item)
       when held == item do
    {key, %{b | state: %{b.state | item: nil}}}
  end

  defp take_item_from_building(key, %{state: %{output_buffer: held}} = b, item)
       when held == item do
    {key, %{b | state: %{b.state | output_buffer: nil}}}
  end

  defp take_item_from_building(_key, _building, _item), do: nil

  # Efficiency boost: chance to not consume input when producing output
  defp apply_efficiency_effects(buildings) do
    Enum.reduce(buildings, buildings, fn {key, building}, acc ->
      eff = Creatures.efficiency_chance(key)

      if eff > 0 and building.state[:output_buffer] != nil do
        # If the building just produced and has efficiency boost,
        # chance to refill input (as if input wasn't consumed)
        if :rand.uniform(100) <= round(eff * 100) do
          case building.type do
            type when type in [:smelter, :refinery, :advanced_smelter, :nuclear_refinery] ->
              # Single-input: can't easily "un-consume" — skip for simplicity
              acc

            _ ->
              acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # Output boost: chance to produce double output
  defp apply_output_effects(buildings, movements) do
    # Find buildings that just pushed output and have output boost
    Enum.reduce(movements, buildings, fn {src_key, _dest_key, item}, acc ->
      building = Map.get(acc, src_key)

      if building do
        output_chance = Creatures.output_chance(src_key)

        if output_chance > 0 and building.state[:output_buffer] == nil and
             (building.state[:output_remaining] || 0) == 0 do
          if :rand.uniform(100) <= round(output_chance * 100) do
            new_state =
              building.state
              |> Map.put(:output_buffer, item)
              |> Map.put(:output_type, item)

            Map.put(acc, src_key, %{building | state: new_state})
          else
            acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
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

        # Unpowered penalty: tier > 0 buildings without power are slower
        boosted =
          if building.type not in [:conveyor, :conveyor_mk2, :conveyor_mk3] do
            tier = ConstructionCosts.tier(building.type)

            if tier > 0 and not Power.powered?(key) do
              boosted * (tier + 1)
            else
              boosted
            end
          else
            boosted
          end

        # Object of Power: logistics_mastery — conveyors 20% faster
        boosted =
          if building.type in [:conveyor, :conveyor_mk2, :conveyor_mk3] and
               building[:owner_id] &&
               ObjectsOfPower.player_has?(building.owner_id, :logistics_mastery) do
            max(1, round(boosted * 0.8))
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
