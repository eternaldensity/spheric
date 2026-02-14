defmodule Spheric.Game.Hiss do
  @moduledoc """
  Hiss corruption system.

  Corruption seeds spawn on distant empty tiles and spread outward over time.
  Corrupted tiles damage/destroy buildings and block new placement.
  Hiss entities spawn from high-corruption zones as hostile creatures.

  Corruption state is stored in an ETS table keyed by tile `{face, row, col}`.
  Each corrupted tile has an intensity level (1-10). Higher intensity means
  faster spread and more dangerous Hiss entity spawns.

  Purification Beacons create corruption-immune zones and slowly push back corruption.
  Defense Turrets auto-attack Hiss entities and drop hiss_residue.
  Player creatures auto-combat Hiss entities when nearby.
  """

  alias Spheric.Game.{WorldStore, Creatures}
  alias Spheric.Geometry.TileNeighbors

  require Logger

  @corruption_table :spheric_corruption
  @hiss_entities_table :spheric_hiss_entities

  # Corruption spreads every N ticks
  @spread_interval 50
  # Corruption seeds appear every N ticks (after world age threshold)
  @seed_interval 200
  # World age (ticks) before corruption starts
  @corruption_start_tick 500
  # Max corruption intensity per tile
  @max_intensity 10
  # Intensity at which Hiss entities can spawn
  @entity_spawn_threshold 7
  # Max number of Hiss entities at once
  @max_hiss_entities 50
  # Hiss entity movement interval (ticks)
  @hiss_move_interval 8
  # Purification beacon immune radius
  @beacon_radius 5
  # Defense turret attack radius
  @turret_radius 3
  # Building damage threshold — buildings on tiles with this intensity+ take damage
  @building_damage_threshold 5
  # Ticks of exposure at damage threshold before building is destroyed
  @building_destroy_ticks 25

  # --- Public API ---

  @doc "Initialize ETS tables for corruption and Hiss entities."
  def init do
    unless :ets.whereis(@corruption_table) != :undefined do
      :ets.new(@corruption_table, [:named_table, :set, :public, read_concurrency: true])
    end

    unless :ets.whereis(@hiss_entities_table) != :undefined do
      :ets.new(@hiss_entities_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Get corruption intensity at a tile. Returns 0 if not corrupted."
  def corruption_at(key) do
    case :ets.whereis(@corruption_table) do
      :undefined ->
        0

      _ ->
        case :ets.lookup(@corruption_table, key) do
          [{^key, data}] -> data.intensity
          [] -> 0
        end
    end
  end

  @doc "Get full corruption data at a tile. Returns nil if not corrupted."
  def get_corruption(key) do
    case :ets.whereis(@corruption_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@corruption_table, key) do
          [{^key, data}] -> data
          [] -> nil
        end
    end
  end

  @doc "Check if a tile is corrupted (intensity > 0)."
  def corrupted?(key), do: corruption_at(key) > 0

  @doc "Check if a tile is blocked from building placement due to corruption."
  def blocks_placement?(key), do: corruption_at(key) > 0

  @doc "Get all corrupted tiles."
  def all_corrupted do
    case :ets.whereis(@corruption_table) do
      :undefined -> []
      _ -> :ets.tab2list(@corruption_table)
    end
  end

  @doc "Get corrupted tiles grouped by face for broadcasting."
  def corrupted_by_face do
    all_corrupted()
    |> Enum.group_by(fn {{face, _r, _c}, _data} -> face end, fn {{face, row, col}, data} ->
      %{face: face, row: row, col: col, intensity: data.intensity}
    end)
  end

  @doc "Get corrupted tiles on a specific face."
  def corrupted_on_face(face_id) do
    case :ets.whereis(@corruption_table) do
      :undefined ->
        []

      _ ->
        :ets.match_object(@corruption_table, {{face_id, :_, :_}, :_})
        |> Enum.map(fn {{face, row, col}, data} ->
          %{face: face, row: row, col: col, intensity: data.intensity}
        end)
    end
  end

  @doc "Count of corrupted tiles."
  def corruption_count do
    case :ets.whereis(@corruption_table) do
      :undefined -> 0
      _ -> :ets.info(@corruption_table, :size)
    end
  end

  # --- Hiss Entities ---

  @doc "Get all Hiss entities."
  def all_hiss_entities do
    case :ets.whereis(@hiss_entities_table) do
      :undefined -> []
      _ -> :ets.tab2list(@hiss_entities_table)
    end
  end

  @doc "Get Hiss entities on a specific face."
  def hiss_entities_on_face(face_id) do
    all_hiss_entities()
    |> Enum.filter(fn {_id, e} -> e.face == face_id end)
  end

  @doc "Count of Hiss entities."
  def hiss_entity_count do
    case :ets.whereis(@hiss_entities_table) do
      :undefined -> 0
      _ -> :ets.info(@hiss_entities_table, :size)
    end
  end

  @doc "Get Hiss entities grouped by face for broadcasting."
  def hiss_entities_by_face do
    all_hiss_entities()
    |> Enum.group_by(fn {_id, e} -> e.face end, fn {id, e} ->
      %{id: id, face: e.face, row: e.row, col: e.col, health: e.health}
    end)
  end

  # --- Tick Processing ---

  @doc """
  Seed new corruption zones. Called periodically from the tick loop.
  Returns list of newly corrupted tiles for broadcasting.
  """
  def maybe_seed_corruption(tick, seed) do
    if tick < @corruption_start_tick or rem(tick, @seed_interval) != 0 do
      []
    else
      do_seed_corruption(tick, seed)
    end
  end

  @doc """
  Spread existing corruption to adjacent tiles.
  Returns list of newly/updated corrupted tiles for broadcasting.
  """
  def spread_corruption(tick) do
    if rem(tick, @spread_interval) != 0 do
      []
    else
      do_spread_corruption(tick)
    end
  end

  @doc """
  Process corruption damage to buildings.
  Returns list of `{key, :damaged | :destroyed}` for broadcasting.
  """
  def process_building_damage(_tick) do
    all_corrupted()
    |> Enum.flat_map(fn {key, data} ->
      if data.intensity >= @building_damage_threshold do
        building = WorldStore.get_building(key)

        if building && building.type not in [:purification_beacon, :defense_turret] do
          damage_ticks = data[:building_damage_ticks] || 0
          # Defense boost from assigned creature reduces damage accumulation
          defense = Creatures.defense_value(key)
          increment = if defense > 0, do: max(0.0, 1.0 - defense), else: 1.0
          new_damage = damage_ticks + increment

          if new_damage >= @building_destroy_ticks do
            # Destroy the building
            WorldStore.remove_building(key)
            # Reset damage counter
            :ets.insert(@corruption_table, {key, %{data | building_damage_ticks: 0}})
            [{key, :destroyed}]
          else
            :ets.insert(@corruption_table, {key, %{data | building_damage_ticks: new_damage}})
            [{key, :damaged}]
          end
        else
          []
        end
      else
        []
      end
    end)
  end

  @doc """
  Spawn Hiss entities from high-corruption zones.
  Returns list of `{id, entity}` for broadcasting.
  """
  def maybe_spawn_hiss_entities(tick, seed) do
    if rem(tick, @spread_interval) != 0 or hiss_entity_count() >= @max_hiss_entities do
      []
    else
      high_corruption =
        all_corrupted()
        |> Enum.filter(fn {key, data} ->
          data.intensity >= @entity_spawn_threshold and
            not WorldStore.has_building?(key)
        end)

      if high_corruption == [] do
        []
      else
        rng = :rand.seed_s(:exsss, {seed, tick, tick * 11})
        # Spawn 1-2 entities per event
        {count, rng} = random_int(rng, 2)
        count = count + 1

        {entities, _rng} =
          Enum.reduce(1..count, {[], rng}, fn _i, {acc, rng} ->
            {idx, rng} = random_int(rng, length(high_corruption))
            {source_key, _data} = Enum.at(high_corruption, idx)
            {face, row, col} = source_key

            id = "hiss:#{tick}:#{face}:#{row}:#{col}"

            entity = %{
              face: face,
              row: row,
              col: col,
              health: 100,
              spawned_at: tick
            }

            :ets.insert(@hiss_entities_table, {id, entity})
            {[{id, entity} | acc], rng}
          end)

        entities
      end
    end
  end

  @doc """
  Move Hiss entities toward nearby buildings/creatures.
  Returns list of `{id, entity}` for broadcasting.
  """
  def move_hiss_entities(tick) do
    if rem(tick, @hiss_move_interval) != 0 do
      []
    else
      n = Application.get_env(:spheric, :subdivisions, 64)

      all_hiss_entities()
      |> Enum.flat_map(fn {id, entity} ->
        # Hiss entities gravitate toward buildings (they want to destroy things)
        dir = rem(:erlang.phash2({tick, id}), 4)

        case TileNeighbors.neighbor({entity.face, entity.row, entity.col}, dir, n) do
          {:ok, {new_face, new_row, new_col}} ->
            updated = %{entity | face: new_face, row: new_row, col: new_col}
            :ets.insert(@hiss_entities_table, {id, updated})
            [{id, updated}]

          :boundary ->
            []
        end
      end)
    end
  end

  @doc """
  Process combat between defense turrets/creatures and Hiss entities.
  Returns `{kills, drops}` where:
  - kills: list of `{entity_id, killer_key}` for broadcasting
  - drops: list of `{key, :hiss_residue}` items dropped by killed entities
  """
  def process_combat(_tick) do
    # Gather turrets and creatures, indexed by face for fast lookup
    turrets_by_face = gather_turrets_by_face()
    creatures_by_face = gather_combat_creatures_by_face()

    hiss = all_hiss_entities()

    {kills, drops} =
      Enum.reduce(hiss, {[], []}, fn {hiss_id, entity}, {kills_acc, drops_acc} ->
        hiss_key = {entity.face, entity.row, entity.col}
        face = entity.face

        # Only check turrets on the same face (within_radius? requires same face)
        turret_hit =
          case Map.get(turrets_by_face, face) do
            nil ->
              nil

            face_turrets ->
              Enum.find(face_turrets, fn {turret_key, _building} ->
                within_radius?(turret_key, hiss_key, @turret_radius)
              end)
          end

        # Only check creatures on the same face
        creature_hit =
          case Map.get(creatures_by_face, face) do
            nil ->
              nil

            face_creatures ->
              Enum.find(face_creatures, fn {creature_key, _creature} ->
                within_radius?(creature_key, hiss_key, 2)
              end)
          end

        cond do
          turret_hit != nil ->
            {turret_key, _} = turret_hit
            # Turret deals 34 damage per tick (kills in 3 ticks)
            new_health = entity.health - 34

            if new_health <= 0 do
              :ets.delete(@hiss_entities_table, hiss_id)

              {[{hiss_id, turret_key} | kills_acc], [{turret_key, :hiss_residue} | drops_acc]}
            else
              :ets.insert(@hiss_entities_table, {hiss_id, %{entity | health: new_health}})
              {kills_acc, drops_acc}
            end

          creature_hit != nil ->
            {_creature_key, creature_info} = creature_hit
            # Creatures deal damage based on their type
            damage = creature_combat_damage(creature_info.type)
            new_health = entity.health - damage

            if new_health <= 0 do
              :ets.delete(@hiss_entities_table, hiss_id)
              {[{hiss_id, :creature} | kills_acc], drops_acc}
            else
              :ets.insert(@hiss_entities_table, {hiss_id, %{entity | health: new_health}})
              {kills_acc, drops_acc}
            end

          true ->
            {kills_acc, drops_acc}
        end
      end)

    {kills, drops}
  end

  @doc """
  Process purification beacons: clear corruption within radius.
  Returns list of purified tile keys for broadcasting.
  """
  def process_purification(_tick) do
    beacons =
      for face_id <- 0..29,
          {key, building} <- WorldStore.get_face_buildings(face_id),
          building.type == :purification_beacon,
          do: key

    if beacons == [] do
      []
    else
      # Single pass: scan corrupted tiles once, check against all beacons
      corrupted = all_corrupted()

      # Group beacons by face for fast same-face filtering
      beacons_by_face =
        Enum.group_by(beacons, fn {face, _r, _c} -> face end)

      corrupted
      |> Enum.flat_map(fn {corrupted_key, data} ->
        {face, _r, _c} = corrupted_key

        # Only check beacons on the same face (within_radius? requires same face)
        case Map.get(beacons_by_face, face) do
          nil ->
            []

          face_beacons ->
            hits =
              Enum.count(face_beacons, fn beacon_key ->
                within_radius?(beacon_key, corrupted_key, @beacon_radius)
              end)

            if hits > 0 do
              # Each beacon in range reduces intensity by 1
              new_intensity = data.intensity - hits

              if new_intensity <= 0 do
                :ets.delete(@corruption_table, corrupted_key)
                [corrupted_key]
              else
                :ets.insert(@corruption_table, {corrupted_key, %{data | intensity: new_intensity}})
                [corrupted_key]
              end
            else
              []
            end
        end
      end)
      |> Enum.uniq()
    end
  end

  @doc "Check if a tile is within a purification beacon's or dimensional stabilizer's protected zone."
  def protected_by_beacon?(key) do
    zones = gather_protection_zones()
    tile_in_protection_zones?(key, zones)
  end

  @doc "Put corruption data directly (used for loading from DB)."
  def put_corruption(key, data) do
    :ets.insert(@corruption_table, {key, data})
  end

  @doc "Put a Hiss entity directly (used for loading from DB)."
  def put_hiss_entity(id, entity) do
    :ets.insert(@hiss_entities_table, {id, entity})
  end

  @doc "Clear all Hiss ETS data (used in tests)."
  def clear_all do
    if :ets.whereis(@corruption_table) != :undefined do
      :ets.delete_all_objects(@corruption_table)
    end

    if :ets.whereis(@hiss_entities_table) != :undefined do
      :ets.delete_all_objects(@hiss_entities_table)
    end
  end

  # --- Internal ---

  # Gather all beacon/stabilizer positions with their radii, grouped by face.
  # Returns %{face_id => [{key, radius}, ...]}
  defp gather_protection_zones do
    stabilizer_radius = Spheric.Game.Behaviors.DimensionalStabilizer.radius()

    zones =
      for face_id <- 0..29,
          {key, building} <- WorldStore.get_face_buildings(face_id),
          building.type in [:purification_beacon, :dimensional_stabilizer] do
        radius =
          if building.type == :dimensional_stabilizer,
            do: stabilizer_radius,
            else: @beacon_radius

        {key, radius}
      end

    Enum.group_by(zones, fn {{face, _r, _c}, _radius} -> face end)
  end

  # Check if a tile falls within any cached protection zone.
  defp tile_in_protection_zones?({face, _r, _c} = key, zones_by_face) do
    case Map.get(zones_by_face, face) do
      nil ->
        false

      face_zones ->
        Enum.any?(face_zones, fn {zone_key, radius} ->
          within_radius?(zone_key, key, radius)
        end)
    end
  end

  defp do_seed_corruption(tick, seed) do
    rng = :rand.seed_s(:exsss, {seed, tick, tick * 13})
    n = Application.get_env(:spheric, :subdivisions, 64)

    # Cache protection zones once for all seed attempts
    zones = gather_protection_zones()

    # Scale seed count with world age (more corruption over time)
    age_factor = div(tick - @corruption_start_tick, 1000) + 1
    seed_count = min(age_factor, 3)

    {new_tiles, _rng} =
      Enum.reduce(1..seed_count, {[], rng}, fn _i, {acc, rng} ->
        {face_id, rng} = random_int(rng, 30)
        {row, rng} = random_int(rng, n)
        {col, rng} = random_int(rng, n)
        key = {face_id, row, col}

        # Don't seed on existing buildings or already-corrupted tiles or beacon zones
        if not WorldStore.has_building?(key) and
             not corrupted?(key) and
             not tile_in_protection_zones?(key, zones) do
          data = %{
            intensity: 1,
            seeded_at: tick,
            building_damage_ticks: 0
          }

          :ets.insert(@corruption_table, {key, data})
          {[{key, data} | acc], rng}
        else
          {acc, rng}
        end
      end)

    new_tiles
  end

  defp do_spread_corruption(tick) do
    n = Application.get_env(:spheric, :subdivisions, 64)

    # Cache protection zones once for entire spread pass
    zones = gather_protection_zones()

    # Snapshot current corrupted tiles (iterate over snapshot, not live table)
    corrupted_snapshot = all_corrupted()

    # Build a set of already-corrupted keys for O(1) membership checks
    corrupted_set = MapSet.new(corrupted_snapshot, fn {key, _data} -> key end)

    corrupted_snapshot
    |> Enum.flat_map(fn {key, data} ->
      if data.intensity < @max_intensity do
        # Increase intensity of existing tile
        new_data = %{data | intensity: min(data.intensity + 1, @max_intensity)}
        :ets.insert(@corruption_table, {key, new_data})

        # Try to spread to adjacent tiles
        spread_targets =
          for dir <- 0..3,
              {:ok, neighbor_key} <- [TileNeighbors.neighbor(key, dir, n)],
              not MapSet.member?(corrupted_set, neighbor_key),
              not tile_in_protection_zones?(neighbor_key, zones),
              not WorldStore.has_building?(neighbor_key) or
                WorldStore.get_building(neighbor_key).type not in [
                  :purification_beacon,
                  :defense_turret
                ] do
            neighbor_key
          end

        # Pick 1-2 neighbors deterministically using hash instead of Enum.shuffle
        targets = pick_spread_targets(spread_targets, key, tick)

        new_corruptions =
          Enum.map(targets, fn target_key ->
            target_data = %{
              intensity: 1,
              seeded_at: data.seeded_at,
              building_damage_ticks: 0
            }

            :ets.insert(@corruption_table, {target_key, target_data})
            {target_key, target_data}
          end)

        [{key, new_data} | new_corruptions]
      else
        []
      end
    end)
  end

  # Pick 1-2 spread targets deterministically using a hash-based selection.
  # Avoids the cost of Enum.shuffle for small lists.
  defp pick_spread_targets([], _key, _tick), do: []
  defp pick_spread_targets([single], _key, _tick), do: [single]

  defp pick_spread_targets(targets, key, tick) do
    len = length(targets)
    hash = :erlang.phash2({key, tick})
    count = rem(hash, 2) + 1
    idx1 = rem(hash, len)

    if count == 1 or len == 1 do
      [Enum.at(targets, idx1)]
    else
      idx2 = rem(Bitwise.bsr(hash, 16), len - 1)
      idx2 = if idx2 >= idx1, do: idx2 + 1, else: idx2
      [Enum.at(targets, idx1), Enum.at(targets, idx2)]
    end
  end

  defp within_radius?({f1, r1, c1}, {f2, r2, c2}, radius) do
    # Simple same-face distance check
    f1 == f2 and abs(r1 - r2) <= radius and abs(c1 - c2) <= radius
  end

  # Gather turrets indexed by face for O(1) face lookup in combat.
  defp gather_turrets_by_face do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        building.type == :defense_turret,
        reduce: %{} do
      acc ->
        Map.update(acc, face_id, [{key, building}], &[{key, building} | &1])
    end
  end

  # Gather combat creatures indexed by face for O(1) face lookup.
  defp gather_combat_creatures_by_face do
    case :ets.whereis(:spheric_player_creatures) do
      :undefined ->
        %{}

      _ ->
        :ets.tab2list(:spheric_player_creatures)
        |> Enum.flat_map(fn {_player_id, roster} ->
          Enum.flat_map(roster, fn creature ->
            if creature.assigned_to do
              [{creature.assigned_to, creature}]
            else
              []
            end
          end)
        end)
        |> Enum.group_by(fn {{face, _r, _c}, _creature} -> face end)
    end
  end

  defp creature_combat_damage(type) do
    case type do
      :ember_wisp -> 25
      :frost_shard -> 20
      :shadow_tendril -> 35
      :static_mote -> 22
      :void_fragment -> 30
      _ -> 15
    end
  end

  defp random_int(rng, max) do
    {roll, rng} = :rand.uniform_s(rng)
    {trunc(roll * max) |> min(max - 1), rng}
  end
end
