defmodule Spheric.Game.Research do
  @moduledoc """
  Research system ("Bureau Case Files").

  Manages progression via item delivery. Buildings are locked behind
  "clearance levels" that players unlock by completing case files.

  Case files require delivering specific items via Submission Terminals.
  Each player tracks their own progress independently.
  """

  import Ecto.Query

  alias Spheric.Repo
  alias Spheric.Game.Schema.ResearchProgress
  alias Spheric.Game.ObjectsOfPower

  require Logger

  # ETS table for runtime unlock state (per-player)
  @unlock_table :spheric_research_unlocks

  # --- Case File Definitions ---

  # Clearance Level 1: Basic Logistics
  # Unlocks: splitter, merger
  @l1_case_files [
    %{
      id: "l1_iron_delivery",
      name: "Ferric Standardization",
      clearance: 1,
      requirements: %{iron_ingot: 50},
      description: "Deliver 50 Ferric Standards to demonstrate basic processing capability."
    },
    %{
      id: "l1_copper_delivery",
      name: "Paraelectric Requisition",
      clearance: 1,
      requirements: %{copper_ingot: 30},
      description: "Deliver 30 Paraelectric Bars for Bureau conduit projects."
    }
  ]

  # Clearance Level 2: Advanced Production
  # Unlocks: assembler, refinery
  @l2_case_files [
    %{
      id: "l2_wire_delivery",
      name: "Fabrication Protocol Alpha",
      clearance: 2,
      requirements: %{wire: 40, plate: 40},
      description: "Deliver 40 Conductive Filaments and 40 Structural Plates to prove fabrication readiness."
    },
    %{
      id: "l2_titanium_delivery",
      name: "Astral Ore Refinement",
      clearance: 2,
      requirements: %{titanium_ingot: 30},
      description: "Deliver 30 Astral Ingots sourced from Astral Rift sectors."
    }
  ]

  # Clearance Level 3: Paranatural (future)
  # Unlocks: future buildings from Phase 3+
  @l3_case_files [
    %{
      id: "l3_advanced_components",
      name: "Paranatural Engineering",
      clearance: 3,
      requirements: %{circuit: 30, frame: 20, polycarbonate: 20},
      description: "Deliver 30 Resonance Circuits, 20 Astral Frames, and 20 Stabilized Polymers to unlock paranatural containment technology."
    }
  ]

  @all_case_files @l1_case_files ++ @l2_case_files ++ @l3_case_files

  @case_file_map Map.new(@all_case_files, fn cf -> {cf.id, cf} end)

  # Buildings unlocked at each clearance level
  @clearance_unlocks %{
    0 => [:conveyor, :miner, :smelter, :submission_terminal],
    1 => [:splitter, :merger],
    2 => [:assembler, :refinery],
    3 => [:containment_trap, :purification_beacon, :defense_turret]
  }

  # --- Public API ---

  @doc "Initialize the ETS unlock table."
  def init do
    unless :ets.whereis(@unlock_table) != :undefined do
      :ets.new(@unlock_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Returns all case file definitions."
  def case_files, do: @all_case_files

  @doc "Returns a specific case file by ID."
  def get_case_file(id), do: Map.get(@case_file_map, id)

  @doc "Returns case files for a specific clearance level."
  def case_files_for_level(level) do
    Enum.filter(@all_case_files, &(&1.clearance == level))
  end

  @doc """
  Get the current clearance level for a player.
  A player has clearance level N if all case files at levels 1..N are completed.
  """
  def clearance_level(player_id) do
    completed = completed_case_file_ids(player_id)

    cond do
      all_completed?(@l3_case_files, completed) -> 3
      all_completed?(@l2_case_files, completed) -> 2
      all_completed?(@l1_case_files, completed) -> 1
      true -> 0
    end
  end

  @doc """
  Returns the list of building types a player can place,
  based on their clearance level.
  """
  def unlocked_buildings(player_id) do
    level = clearance_level(player_id)

    0..level
    |> Enum.flat_map(&Map.get(@clearance_unlocks, &1, []))
  end

  @doc """
  Check if a player can place a specific building type.
  """
  def can_place?(player_id, building_type) do
    building_type in unlocked_buildings(player_id)
  end

  @doc """
  Submit an item to research progress. Called when a submission terminal
  consumes an item.

  Returns `{:ok, updated_submissions}` or `{:completed, case_file_id}` if
  the submission completes a case file, or `:no_match` if no case file
  needs this item.
  """
  def submit_item(world_id, player_id, item_type) do
    # Find case files that need this item and aren't completed
    completed = completed_case_file_ids(player_id)
    progress_map = get_progress_map(world_id, player_id)

    eligible =
      @all_case_files
      |> Enum.filter(fn cf ->
        cf.id not in completed and
          Map.has_key?(cf.requirements, item_type)
      end)
      |> Enum.sort_by(& &1.clearance)

    case eligible do
      [] ->
        :no_match

      [case_file | _] ->
        current = Map.get(progress_map, case_file.id, %{})
        current_count = Map.get(current, Atom.to_string(item_type), 0)
        required = Map.get(case_file.requirements, item_type, 0)

        new_count = min(current_count + 1, required)
        new_submissions = Map.put(current, Atom.to_string(item_type), new_count)

        save_progress(world_id, player_id, case_file.id, new_submissions)

        # Check if this case file is now complete
        if case_file_complete?(case_file, new_submissions) do
          mark_completed(world_id, player_id, case_file.id, new_submissions)
          refresh_unlock_cache(player_id)

          # Check if entire clearance tier is now complete → grant Object of Power
          check_clearance_complete(world_id, player_id, case_file.clearance)

          {:completed, case_file.id}
        else
          {:ok, new_submissions}
        end
    end
  end

  @doc """
  Get research progress for a player across all case files.
  Returns a map of case_file_id => %{submissions: %{}, completed: bool}.
  """
  def get_player_progress(world_id, player_id) do
    ResearchProgress
    |> where([rp], rp.world_id == ^world_id and rp.player_id == ^player_id)
    |> Repo.all()
    |> Map.new(fn rp ->
      {rp.case_file_id,
       %{submissions: atomize_submissions(rp.submissions), completed: rp.completed}}
    end)
  end

  @doc """
  Load all research progress from DB into ETS cache for a player.
  Called during player connection.
  """
  def load_player_unlocks(world_id, player_id) do
    init()
    progress = get_player_progress(world_id, player_id)

    completed_ids =
      progress
      |> Enum.filter(fn {_id, p} -> p.completed end)
      |> Enum.map(fn {id, _p} -> id end)
      |> MapSet.new()

    :ets.insert(@unlock_table, {player_id, completed_ids})

    # Re-derive Objects of Power from completed case files
    ObjectsOfPower.init()

    for level <- 1..3 do
      tier_files = case_files_for_level(level)

      if all_completed?(tier_files, completed_ids) do
        ObjectsOfPower.grant(player_id, level)
      end
    end

    :ok
  end

  @doc """
  Get progress summary for UI display.
  Returns list of case file info with progress for a player.
  """
  def progress_summary(world_id, player_id) do
    progress = get_player_progress(world_id, player_id)

    Enum.map(@all_case_files, fn cf ->
      player_progress = Map.get(progress, cf.id, %{submissions: %{}, completed: false})

      requirements_with_progress =
        Enum.map(cf.requirements, fn {item, required} ->
          submitted = Map.get(player_progress.submissions, item, 0)
          %{item: item, required: required, submitted: submitted}
        end)

      %{
        id: cf.id,
        name: cf.name,
        clearance: cf.clearance,
        description: cf.description,
        completed: player_progress.completed,
        requirements: requirements_with_progress
      }
    end)
  end

  # --- Internal ---

  defp completed_case_file_ids(player_id) do
    case :ets.whereis(@unlock_table) do
      :undefined ->
        MapSet.new()

      _ ->
        case :ets.lookup(@unlock_table, player_id) do
          [{^player_id, completed}] -> completed
          [] -> MapSet.new()
        end
    end
  end

  defp all_completed?(case_files, completed_ids) do
    Enum.all?(case_files, fn cf -> cf.id in completed_ids end)
  end

  defp get_progress_map(world_id, player_id) do
    ResearchProgress
    |> where([rp], rp.world_id == ^world_id and rp.player_id == ^player_id)
    |> Repo.all()
    |> Map.new(fn rp -> {rp.case_file_id, rp.submissions} end)
  end

  defp save_progress(world_id, player_id, case_file_id, submissions) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      ResearchProgress,
      [
        %{
          world_id: world_id,
          player_id: player_id,
          case_file_id: case_file_id,
          submissions: submissions,
          completed: false,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:submissions, :updated_at]},
      conflict_target: [:world_id, :player_id, :case_file_id]
    )
  end

  defp mark_completed(world_id, player_id, case_file_id, submissions) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      ResearchProgress,
      [
        %{
          world_id: world_id,
          player_id: player_id,
          case_file_id: case_file_id,
          submissions: submissions,
          completed: true,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:submissions, :completed, :updated_at]},
      conflict_target: [:world_id, :player_id, :case_file_id]
    )

    Logger.info("Player #{player_id} completed case file: #{case_file_id}")
  end

  defp check_clearance_complete(_world_id, player_id, clearance_level) do
    completed = completed_case_file_ids(player_id)
    tier_files = case_files_for_level(clearance_level)

    if all_completed?(tier_files, completed) do
      ObjectsOfPower.grant(player_id, clearance_level)
    end
  end

  defp refresh_unlock_cache(player_id) do
    completed = completed_case_file_ids(player_id)
    :ets.insert(@unlock_table, {player_id, completed})
  end

  defp case_file_complete?(case_file, submissions) do
    Enum.all?(case_file.requirements, fn {item, required} ->
      submitted = Map.get(submissions, Atom.to_string(item), 0)
      submitted >= required
    end)
  end

  defp atomize_submissions(submissions) when is_map(submissions) do
    Map.new(submissions, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end)
  end

  defp atomize_submissions(_), do: %{}
end
