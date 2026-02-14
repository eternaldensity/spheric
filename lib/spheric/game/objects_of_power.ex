defmodule Spheric.Game.ObjectsOfPower do
  @moduledoc """
  Objects of Power — milestone rewards for completing all case files
  in a clearance tier.

  L1 complete: Bureau Directive Alpha — global +10% production speed
  L2 complete: Pneumatic Transit Network — teleport between owned terminals
  L3 complete: Astral Projection — see all creature locations on sphere
  """

  @table :spheric_objects_of_power

  @objects %{
    1 => %{
      id: :production_surge,
      name: "Bureau Directive Alpha",
      description: "Global +10% production speed for all your structures",
      clearance: 1
    },
    2 => %{
      id: :terminal_network,
      name: "Pneumatic Transit Network",
      description: "Teleport between owned Submission Terminals",
      clearance: 2
    },
    3 => %{
      id: :creature_sight,
      name: "Astral Projection",
      description: "See all creature locations on the sphere",
      clearance: 3
    },
    4 => %{
      id: :power_surge,
      name: "Power Surge",
      description: "+25% generator fuel duration",
      clearance: 4
    },
    5 => %{
      id: :logistics_mastery,
      name: "Logistics Mastery",
      description: "All conveyors operate 20% faster",
      clearance: 5
    },
    6 => %{
      id: :altered_resonance,
      name: "Altered Resonance",
      description: "Altered item effects are doubled",
      clearance: 6
    },
    7 => %{
      id: :entity_communion,
      name: "Entity Communion",
      description: "+50% creature boost stacking",
      clearance: 7
    },
    8 => %{
      id: :boards_favor,
      name: "Board's Favor",
      description: "Corruption cannot seed within 10 tiles of your buildings",
      clearance: 8
    }
  }

  def init do
    unless :ets.whereis(@table) != :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Get the Object of Power definition for a clearance level."
  def get(clearance_level), do: Map.get(@objects, clearance_level)

  @doc "All object definitions."
  def all, do: @objects

  @doc "Grant an Object of Power to a player."
  def grant(player_id, clearance_level) do
    object = get(clearance_level)

    if object do
      existing = player_objects(player_id)

      unless Enum.any?(existing, &(&1.id == object.id)) do
        :ets.insert(@table, {{player_id, object.id}, object})

        Phoenix.PubSub.broadcast(
          Spheric.PubSub,
          "research:#{player_id}",
          {:object_of_power_granted, object}
        )
      end
    end

    :ok
  end

  @doc "Check if a player has a specific Object of Power."
  def player_has?(player_id, object_id) do
    case :ets.lookup(@table, {player_id, object_id}) do
      [_] -> true
      [] -> false
    end
  end

  @doc "Get all Objects of Power granted to a player."
  def player_objects(player_id) do
    # Match all entries for this player
    :ets.match_object(@table, {{player_id, :_}, :_})
    |> Enum.map(fn {_key, object} -> object end)
  end

  @doc "Get all granted objects (for persistence)."
  def all_grants do
    :ets.tab2list(@table)
  end

  @doc "Bulk insert grants (from persistence)."
  def put_all(entries) do
    :ets.insert(@table, entries)
    :ok
  end

  @doc "Clear all grants (for fresh start)."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
