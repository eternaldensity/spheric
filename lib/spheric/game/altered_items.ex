defmodule Spheric.Game.AlteredItems do
  @moduledoc """
  Altered Items — rare paranatural objects scattered across the sphere.

  ~0.1% of tiles contain an Altered Item. When a building is placed on an
  Altered Item tile, the building gains a permanent special effect.

  Effects:
  - overclock: 2x production speed (halved tick rate)
  - duplication: 5% chance to duplicate output items
  - purified_smelting: smelter/refinery produces 2x output per input
  - trap_radius: triple containment trap capture radius (3 → 9)
  - teleport_output: output items skip one building downstream
  """

  @table :spheric_altered_items
  @density 0.001

  @altered_types %{
    overclock: %{
      id: :overclock,
      name: "Resonance Accelerator",
      description: "2x production speed for attached structure",
      color: 0xFF4444
    },
    duplication: %{
      id: :duplication,
      name: "Probability Fracture",
      description: "5% chance to duplicate output items",
      color: 0x44FF88
    },
    purified_smelting: %{
      id: :purified_smelting,
      name: "Thermal Anomaly",
      description: "Processing yields 2x output per input",
      color: 0xFF8844
    },
    trap_radius: %{
      id: :trap_radius,
      name: "Spatial Distortion",
      description: "Triple containment capture radius",
      color: 0xAA44FF
    },
    teleport_output: %{
      id: :teleport_output,
      name: "Shifting Anchor",
      description: "Output bypasses next downstream structure",
      color: 0x4488FF
    }
  }

  @type_ids Map.keys(@altered_types)

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  def types, do: @altered_types
  def type_ids, do: @type_ids

  def get_type(id), do: Map.get(@altered_types, id)

  @doc "Get the altered item at a tile, or nil."
  def get(tile_key) do
    case :ets.lookup(@table, tile_key) do
      [{^tile_key, type_id}] -> Map.get(@altered_types, type_id)
      [] -> nil
    end
  end

  @doc "Store an altered item at a tile."
  def put(tile_key, type_id) do
    :ets.insert(@table, {tile_key, type_id})
    :ok
  end

  @doc "Get all altered items (for persistence/streaming)."
  def all do
    :ets.tab2list(@table)
  end

  @doc "Bulk insert altered items (from persistence or world gen)."
  def put_all(entries) do
    :ets.insert(@table, entries)
    :ok
  end

  @doc "Clear all altered items (for fresh world gen)."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Place altered items across the world during generation.
  Uses seeded RNG for deterministic placement.

  Returns {count, rng} where count is the number of items placed.
  """
  def generate(rng, subdivisions \\ 64) do
    {count, rng} =
      Enum.reduce(0..29, {0, rng}, fn face_id, {count, rng} ->
        Enum.reduce(0..(subdivisions - 1), {count, rng}, fn row, {count, rng} ->
          Enum.reduce(0..(subdivisions - 1), {count, rng}, fn col, {count, rng} ->
            {roll, rng} = :rand.uniform_s(rng)

            if roll < @density do
              {type_roll, rng} = :rand.uniform_s(rng)
              type_id = pick_type(type_roll)
              put({face_id, row, col}, type_id)
              {count + 1, rng}
            else
              {count, rng}
            end
          end)
        end)
      end)

    {count, rng}
  end

  defp pick_type(roll) do
    # Equal probability among all types
    types = @type_ids
    index = min(trunc(roll * length(types)), length(types) - 1)
    Enum.at(types, index)
  end

  @doc "Get all altered items for a given face (for terrain streaming)."
  def get_face_items(face_id) do
    :ets.match_object(@table, {{face_id, :_, :_}, :_})
  end
end
