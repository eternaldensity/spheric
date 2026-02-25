defmodule Spheric.Game.Creatures do
  @moduledoc """
  Creature system ("Altered Entities").

  Manages wild creatures that roam the sphere, can be captured via
  Containment Traps, and assigned to buildings for production boosts.

  Creatures are stored in two ETS tables:
  - `:spheric_creatures` — wild creatures on the map, keyed by unique ID
  - `:spheric_player_creatures` — captured creatures per player
  """

  alias Spheric.Game.WorldStore
  alias Spheric.Geometry.TileNeighbors

  require Logger

  @creatures_table :spheric_creatures
  @player_creatures_table :spheric_player_creatures
  @assignments_table :spheric_creature_assignments

  # --- Creature Type Definitions ---

  @creature_types %{
    ember_wisp: %{
      name: "Ember Wisp",
      biomes: [:volcanic, :desert],
      boost_type: :speed,
      boost_amount: 0.40,
      flavor: "Fire-aligned paranatural entity",
      color: 0xFF6622
    },
    frost_shard: %{
      name: "Frost Shard",
      biomes: [:tundra],
      boost_type: :speed,
      boost_amount: 0.30,
      flavor: "Cryogenic anomaly",
      color: 0x88CCFF
    },
    quartz_drone: %{
      name: "Quartz Drone",
      biomes: [:tundra, :forest],
      boost_type: :efficiency,
      boost_amount: 0.25,
      flavor: "Resonance-attuned construct",
      color: 0xD4B8FF
    },
    shadow_tendril: %{
      name: "Shadow Tendril",
      biomes: [:forest],
      boost_type: :defense,
      boost_amount: 1.0,
      flavor: "Darkness-adapted entity",
      color: 0x332244
    },
    copper_beetle: %{
      name: "Copper Beetle",
      biomes: [:grassland],
      boost_type: :output,
      boost_amount: 0.20,
      flavor: "Metallovore specimen",
      color: 0xDD8844
    },
    spore_cloud: %{
      name: "Spore Cloud",
      biomes: [:forest, :grassland],
      boost_type: :area,
      boost_amount: 0.50,
      flavor: "Biological dispersal entity",
      color: 0x66AA44
    },
    static_mote: %{
      name: "Static Mote",
      biomes: [:desert],
      boost_type: :speed,
      boost_amount: 0.35,
      flavor: "Electromagnetic anomaly",
      color: 0xFFFF44
    },
    void_fragment: %{
      name: "Void Fragment",
      biomes: [:volcanic],
      boost_type: :all,
      boost_amount: 0.15,
      flavor: "Extradimensional residue",
      color: 0x220044
    },
    flux_serpent: %{
      name: "Flux Serpent",
      biomes: [:volcanic, :desert],
      boost_type: :speed,
      boost_amount: 0.50,
      flavor: "High-energy paranatural entity drawn to radiant deposits",
      color: 0xFF44AA
    },
    resonance_moth: %{
      name: "Resonance Moth",
      biomes: [:forest, :grassland, :tundra],
      boost_type: :efficiency,
      boost_amount: 0.35,
      flavor: "Delicate anomaly that optimizes paranatural processes",
      color: 0xAAFFDD
    },
    iron_golem: %{
      name: "Ferric Sentinel",
      biomes: [:grassland, :volcanic],
      boost_type: :defense,
      boost_amount: 1.0,
      flavor: "Massive metallovore, highly protective of its territory",
      color: 0x888899
    },
    phase_wisp: %{
      name: "Phase Wisp",
      biomes: [:tundra, :desert],
      boost_type: :area,
      boost_amount: 0.60,
      flavor: "Extradimensional entity that warps local space",
      color: 0x44FFFF
    }
  }

  @creature_type_atoms Map.keys(@creature_types)

  # Spawning constants
  @spawn_interval 25
  @max_wild_creatures 200
  @move_interval 5
  @capture_radius 3
  @capture_time 15

  # Evolution: creatures assigned for this many seconds evolve (2x boost)
  @evolution_threshold_seconds 600
  # Check evolution every N ticks
  @evolution_check_interval 50

  # --- Public API ---

  @doc "Initialize ETS tables for creatures."
  def init do
    unless :ets.whereis(@creatures_table) != :undefined do
      :ets.new(@creatures_table, [:named_table, :set, :public, read_concurrency: true])
    end

    unless :ets.whereis(@player_creatures_table) != :undefined do
      :ets.new(@player_creatures_table, [:named_table, :set, :public, read_concurrency: true])
    end

    # Reverse index: building_key -> creature (for O(1) lookup in tick loop)
    unless :ets.whereis(@assignments_table) != :undefined do
      :ets.new(@assignments_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Returns all creature type definitions."
  def creature_types, do: @creature_types

  @doc "Returns the definition for a specific creature type."
  def creature_type(type), do: Map.get(@creature_types, type)

  @doc "Returns the display name for a creature type."
  def display_name(type) do
    case Map.get(@creature_types, type) do
      nil -> Atom.to_string(type)
      info -> info.name
    end
  end

  @doc "Returns the boost info for a creature type."
  def boost_info(type) do
    case Map.get(@creature_types, type) do
      nil -> nil
      info -> %{type: info.boost_type, amount: info.boost_amount}
    end
  end

  # --- Wild Creature Management ---

  @doc "Get all wild creatures."
  def all_wild_creatures do
    case :ets.whereis(@creatures_table) do
      :undefined -> []
      _ -> :ets.tab2list(@creatures_table)
    end
  end

  @doc "Get a wild creature by ID."
  def get_wild_creature(id) do
    case :ets.whereis(@creatures_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@creatures_table, id) do
          [{^id, creature}] -> creature
          [] -> nil
        end
    end
  end

  @doc "Get all wild creatures on a specific face."
  def wild_creatures_on_face(face_id) do
    all_wild_creatures()
    |> Enum.filter(fn {_id, c} -> c.face == face_id end)
  end

  @doc "Count of wild creatures."
  def wild_creature_count do
    case :ets.whereis(@creatures_table) do
      :undefined -> 0
      _ -> :ets.info(@creatures_table, :size)
    end
  end

  @doc """
  Attempt to spawn new wild creatures. Called periodically from the tick loop.
  Returns list of spawned creature data for broadcasting.
  """
  def maybe_spawn(tick, seed) do
    if rem(tick, @spawn_interval) != 0 or wild_creature_count() >= @max_wild_creatures do
      []
    else
      do_spawn(tick, seed)
    end
  end

  @doc """
  Move all wild creatures. Called every @move_interval ticks.
  Returns list of creature updates for broadcasting.
  """
  def move_creatures(tick) do
    if rem(tick, @move_interval) != 0 do
      []
    else
      n = Application.get_env(:spheric, :subdivisions, 64)

      # Find gathering posts for creature attraction
      gathering_posts = find_gathering_posts()

      all_wild_creatures()
      |> Enum.flat_map(fn {id, creature} ->
        # 30% chance to move toward nearest gathering post within radius 7
        dir =
          if :erlang.phash2({tick, id, :bias}) < round(0.3 * 4_294_967_295) do
            case nearest_gathering_post(creature, gathering_posts, 7) do
              nil -> rem(:erlang.phash2({tick, id}), 4)
              post -> direction_toward(creature, post)
            end
          else
            rem(:erlang.phash2({tick, id}), 4)
          end

        case TileNeighbors.neighbor({creature.face, creature.row, creature.col}, dir, n) do
          {:ok, {new_face, new_row, new_col}} ->
            # Don't move onto tiles with buildings
            if WorldStore.has_building?({new_face, new_row, new_col}) do
              []
            else
              updated = %{creature | face: new_face, row: new_row, col: new_col}
              :ets.insert(@creatures_table, {id, updated})
              [{id, updated}]
            end

          :boundary ->
            []
        end
      end)
    end
  end

  defp find_gathering_posts do
    for face_id <- 0..29,
        {key, building} <- WorldStore.get_face_buildings(face_id),
        building.type == :gathering_post,
        do: {key, building}
  end

  defp nearest_gathering_post(creature, posts, radius) do
    posts
    |> Enum.filter(fn {{face, row, col}, _building} ->
      creature.face == face and
        abs(creature.row - row) <= radius and
        abs(creature.col - col) <= radius
    end)
    |> Enum.sort_by(fn {{_face, row, col}, _building} ->
      abs(creature.row - row) + abs(creature.col - col)
    end)
    |> case do
      [{key, _} | _] -> key
      [] -> nil
    end
  end

  defp direction_toward(creature, {_face, target_row, target_col}) do
    dr = target_row - creature.row
    dc = target_col - creature.col

    # 0=up, 1=right, 2=down, 3=left
    if abs(dr) >= abs(dc) do
      if dr > 0, do: 2, else: 0
    else
      if dc > 0, do: 1, else: 3
    end
  end

  @doc """
  Process containment traps: check if any wild creatures are within
  capture radius and progress capture timers.
  Returns list of `{trap_key, creature_id, creature}` for newly captured creatures.
  """
  def process_traps(_tick) do
    # Gather all containment trap buildings
    traps =
      for face_id <- 0..29,
          {key, building} <- WorldStore.get_face_buildings(face_id),
          building.type == :containment_trap,
          do: {key, building}

    Enum.flat_map(traps, fn {trap_key, trap} ->
      {trap_face, trap_row, trap_col} = trap_key

      # Altered item: trap_radius triples the capture radius (3 -> 9)
      # Resonance Cascade doubles the multiplier, Altered Resonance OoP doubles it again
      radius =
        if trap.state[:altered_effect] == :trap_radius do
          base_mult = 3
          base_mult = if Spheric.Game.WorldEvents.active?(:resonance_cascade), do: base_mult * 2, else: base_mult

          mult =
            if trap[:owner_id] &&
                 Spheric.Game.ObjectsOfPower.player_has?(trap.owner_id, :altered_resonance),
              do: base_mult * 2,
              else: base_mult

          @capture_radius * mult
        else
          @capture_radius
        end

      # Find nearest wild creature within radius
      nearest =
        all_wild_creatures()
        |> Enum.filter(fn {_id, c} ->
          # Simple Manhattan-ish distance check on same face
          c.face == trap_face and
            abs(c.row - trap_row) <= radius and
            abs(c.col - trap_col) <= radius
        end)
        |> Enum.sort_by(fn {_id, c} ->
          abs(c.row - trap_row) + abs(c.col - trap_col)
        end)

      case nearest do
        [] ->
          # Reset capture progress if no creature nearby
          if trap.state.capture_progress > 0 do
            new_state = %{trap.state | capturing: nil, capture_progress: 0}
            WorldStore.put_building(trap_key, %{trap | state: new_state})
          end

          []

        [{creature_id, creature} | _] ->
          # Progress capture timer
          current_target = trap.state.capturing
          progress = trap.state.capture_progress

          {new_target, new_progress} =
            if current_target == creature_id do
              {creature_id, progress + 1}
            else
              # New target, reset progress
              {creature_id, 1}
            end

          if new_progress >= @capture_time do
            # Capture complete!
            capture_creature(creature_id, creature, trap.owner_id)

            new_state = %{trap.state | capturing: nil, capture_progress: 0}
            WorldStore.put_building(trap_key, %{trap | state: new_state})

            [{trap_key, creature_id, creature}]
          else
            new_state = %{trap.state | capturing: new_target, capture_progress: new_progress}
            WorldStore.put_building(trap_key, %{trap | state: new_state})
            []
          end
      end
    end)
  end

  @doc "Remove a wild creature from the map and add to player's roster."
  def capture_creature(creature_id, creature, player_id) do
    :ets.delete(@creatures_table, creature_id)

    captured = %{
      id: creature_id,
      type: creature.type,
      assigned_to: nil,
      captured_at: System.system_time(:second)
    }

    roster = get_player_roster(player_id)
    :ets.insert(@player_creatures_table, {player_id, [captured | roster]})

    Logger.info("Creature #{creature.type} (#{creature_id}) captured by #{player_id}")
  end

  @doc "Get a player's creature roster."
  def get_player_roster(player_id) do
    case :ets.whereis(@player_creatures_table) do
      :undefined ->
        []

      _ ->
        case :ets.lookup(@player_creatures_table, player_id) do
          [{^player_id, roster}] -> roster
          [] -> []
        end
    end
  end

  @doc """
  Assign a creature from a player's roster to a building.
  Returns :ok or {:error, reason}.
  """
  def assign_creature(player_id, creature_id, building_key) do
    roster = get_player_roster(player_id)

    case Enum.find(roster, fn c -> c.id == creature_id end) do
      nil ->
        {:error, :creature_not_found}

      _creature ->
        building = WorldStore.get_building(building_key)

        cond do
          building == nil ->
            {:error, :no_building}

          building.owner_id != player_id ->
            {:error, :not_owner}

          building.type in [:conveyor, :containment_trap, :submission_terminal] ->
            {:error, :invalid_building_type}

          has_assigned_creature?(building_key) ->
            {:error, :already_assigned}

          true ->
            # Update roster
            updated_roster =
              Enum.map(roster, fn c ->
                if c.id == creature_id do
                  %{c | assigned_to: building_key}
                else
                  c
                end
              end)

            :ets.insert(@player_creatures_table, {player_id, updated_roster})
            # Update reverse index
            assigned = Enum.find(updated_roster, fn c -> c.id == creature_id end)
            if assigned, do: :ets.insert(@assignments_table, {building_key, assigned})
            :ok
        end
    end
  end

  @doc """
  Unassign a creature from a building, returning it to the roster.
  """
  def unassign_creature(player_id, creature_id) do
    roster = get_player_roster(player_id)

    case Enum.find(roster, fn c -> c.id == creature_id end) do
      nil ->
        {:error, :creature_not_found}

      creature ->
        # Remove from reverse index
        if creature.assigned_to, do: :ets.delete(@assignments_table, creature.assigned_to)

        updated_roster =
          Enum.map(roster, fn c ->
            if c.id == creature_id do
              %{c | assigned_to: nil}
            else
              c
            end
          end)

        :ets.insert(@player_creatures_table, {player_id, updated_roster})
        :ok
    end
  end

  @doc "Check if a building has an assigned creature."
  def has_assigned_creature?(building_key) do
    get_assigned_creature(building_key) != nil
  end

  @doc "Get the creature assigned to a building, if any."
  def get_assigned_creature(building_key) do
    case :ets.whereis(@assignments_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@assignments_table, building_key) do
          [{^building_key, creature}] -> creature
          [] -> nil
        end
    end
  end

  @doc """
  Calculate the effective tick rate for a building, considering any
  assigned creature boost.

  Returns the modified rate (lower = faster production).
  """
  def boosted_rate(building_key, base_rate, owner_id \\ nil) do
    case get_assigned_creature(building_key) do
      nil ->
        base_rate

      creature ->
        case Map.get(@creature_types, creature.type) do
          nil ->
            base_rate

          info ->
            # Evolved creatures get 2x boost
            multiplier = if creature[:evolved], do: 2.0, else: 1.0

            # Object of Power: Entity Communion gives +50% creature boost
            communion_bonus = communion_multiplier(owner_id)

            case info.boost_type do
              :speed ->
                boost = info.boost_amount * multiplier * communion_bonus
                max(1, round(base_rate * (1.0 - boost)))

              :all ->
                boost = info.boost_amount * multiplier * communion_bonus
                max(1, round(base_rate * (1.0 - boost)))

              # Efficiency/output/defense/area don't affect tick rate
              _ ->
                base_rate
            end
        end
    end
  end

  @doc """
  Check if an assigned creature grants an efficiency bonus (chance to not consume input).
  Returns the efficiency chance (0.0-1.0) or 0.0 if none.
  """
  def efficiency_chance(building_key, owner_id \\ nil) do
    get_boost_value(building_key, :efficiency, owner_id)
  end

  @doc """
  Check if an assigned creature grants an output bonus (chance to produce double output).
  Returns the output chance (0.0-1.0) or 0.0 if none.
  """
  def output_chance(building_key, owner_id \\ nil) do
    get_boost_value(building_key, :output, owner_id)
  end

  @doc """
  Get the defense value for a building's assigned creature.
  Returns the defense value (0.0+) or 0.0 if none.
  """
  def defense_value(building_key, owner_id \\ nil) do
    get_boost_value(building_key, :defense, owner_id)
  end

  @doc """
  Get the area multiplier for a building's assigned creature.
  Returns the area multiplier (0.0+) or 0.0 if none.
  """
  def area_value(building_key, owner_id \\ nil) do
    get_boost_value(building_key, :area, owner_id)
  end

  defp get_boost_value(building_key, target_type, owner_id) do
    case get_assigned_creature(building_key) do
      nil ->
        0.0

      creature ->
        case Map.get(@creature_types, creature.type) do
          nil ->
            0.0

          info ->
            multiplier = if creature[:evolved], do: 2.0, else: 1.0
            communion_bonus = communion_multiplier(owner_id)

            if info.boost_type == target_type or info.boost_type == :all do
              info.boost_amount * multiplier * communion_bonus
            else
              0.0
            end
        end
    end
  end

  # Object of Power: Entity Communion gives +50% creature boost stacking
  defp communion_multiplier(nil), do: 1.0

  defp communion_multiplier(owner_id) do
    if Spheric.Game.ObjectsOfPower.player_has?(owner_id, :entity_communion), do: 1.5, else: 1.0
  end

  @doc """
  Get creature data grouped by face for broadcasting.
  Returns map of face_id => list of creature data.
  """
  def creatures_by_face do
    all_wild_creatures()
    |> Enum.group_by(fn {_id, c} -> c.face end, fn {id, c} ->
      %{id: id, type: c.type, face: c.face, row: c.row, col: c.col}
    end)
  end

  @doc "Put a wild creature directly (used for loading from DB)."
  def put_wild_creature(id, creature) do
    :ets.insert(@creatures_table, {id, creature})
  end

  @doc "Put a player's roster directly (used for loading from DB)."
  def put_player_roster(player_id, roster) do
    # Clear old assignments for this player from reverse index
    old_roster = get_player_roster(player_id)
    for c <- old_roster, c.assigned_to != nil do
      :ets.delete(@assignments_table, c.assigned_to)
    end

    :ets.insert(@player_creatures_table, {player_id, roster})

    # Rebuild reverse index entries for assigned creatures
    for c <- roster, c.assigned_to != nil do
      :ets.insert(@assignments_table, {c.assigned_to, c})
    end
  end

  @doc """
  Check for creature evolution. Creatures assigned to buildings for
  a sustained period evolve into stronger forms (2x boost).
  Called periodically from the tick loop.
  Returns list of `{player_id, creature_id, creature_type}` for evolved creatures.
  """
  def process_evolution(tick) do
    if rem(tick, @evolution_check_interval) != 0 do
      []
    else
      now = System.system_time(:second)

      case :ets.whereis(@player_creatures_table) do
        :undefined ->
          []

        _ ->
          :ets.tab2list(@player_creatures_table)
          |> Enum.flat_map(fn {player_id, roster} ->
            {evolved_list, updated_roster, changed?} =
              Enum.reduce(roster, {[], [], false}, fn creature, {evol, rost, changed} ->
                if creature.assigned_to != nil and
                     not (creature[:evolved] || false) and
                     creature[:captured_at] != nil and
                     now - creature.captured_at >= @evolution_threshold_seconds do
                  evolved = Map.put(creature, :evolved, true)
                  {[{player_id, creature.id, creature.type} | evol], [evolved | rost], true}
                else
                  {evol, [creature | rost], changed}
                end
              end)

            if changed? do
              :ets.insert(@player_creatures_table, {player_id, Enum.reverse(updated_roster)})
            end

            evolved_list
          end)
      end
    end
  end

  @doc "Check if a creature is evolved."
  def evolved?(creature), do: creature[:evolved] || false

  @doc "Clear all creature ETS data (used in tests)."
  def clear_all do
    if :ets.whereis(@creatures_table) != :undefined do
      :ets.delete_all_objects(@creatures_table)
    end

    if :ets.whereis(@player_creatures_table) != :undefined do
      :ets.delete_all_objects(@player_creatures_table)
    end

    if :ets.whereis(@assignments_table) != :undefined do
      :ets.delete_all_objects(@assignments_table)
    end
  end

  # --- Internal ---

  defp do_spawn(tick, seed) do
    rng = :rand.seed_s(:exsss, {seed, tick, tick * 7})
    n = Application.get_env(:spheric, :subdivisions, 64)

    # Spawn 1-3 creatures per spawn event
    {count, rng} = spawn_count(rng)

    {creatures, _rng} =
      Enum.reduce(1..count, {[], rng}, fn _i, {acc, rng} ->
        {face_id, rng} = random_int(rng, 30)
        {row, rng} = random_int(rng, n)
        {col, rng} = random_int(rng, n)

        tile = WorldStore.get_tile({face_id, row, col})

        if tile && !WorldStore.has_building?({face_id, row, col}) do
          biome = tile.terrain
          {creature_type, rng} = pick_creature_for_biome(rng, biome)

          if creature_type do
            id = "creature:#{tick}:#{face_id}:#{row}:#{col}"

            creature = %{
              type: creature_type,
              face: face_id,
              row: row,
              col: col,
              spawned_at: tick
            }

            :ets.insert(@creatures_table, {id, creature})
            {[{id, creature} | acc], rng}
          else
            {acc, rng}
          end
        else
          {acc, rng}
        end
      end)

    creatures
  end

  defp spawn_count(rng) do
    {roll, rng} = :rand.uniform_s(rng)

    count =
      cond do
        roll < 0.5 -> 1
        roll < 0.85 -> 2
        true -> 3
      end

    {count, rng}
  end

  defp pick_creature_for_biome(rng, biome) do
    eligible =
      @creature_type_atoms
      |> Enum.filter(fn type ->
        info = Map.get(@creature_types, type)
        biome in info.biomes
      end)

    case eligible do
      [] ->
        {nil, rng}

      types ->
        {idx, rng} = random_int(rng, length(types))
        {Enum.at(types, idx), rng}
    end
  end

  defp random_int(rng, max) do
    {roll, rng} = :rand.uniform_s(rng)
    {trunc(roll * max) |> min(max - 1), rng}
  end
end
