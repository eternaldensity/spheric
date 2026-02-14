defmodule Spheric.Game.BoardContact do
  @moduledoc """
  Board Contact — cooperative endgame quest.

  The ultimate goal: all players contribute massive amounts of advanced items
  to achieve "contact" with The Board. This is a server-wide collaborative
  effort tracked across all players.

  Requirements are intentionally massive to require multi-player cooperation.
  """

  require Logger

  @contact_table :spheric_board_contact

  # The endgame requirements — massive cooperative item production
  @requirements %{
    board_resonator: 10,
    supercomputer: 50,
    dimensional_core: 20,
    advanced_composite: 100,
    nuclear_cell: 50,
    containment_module: 30,
    creature_essence: 200,
    hiss_residue: 100
  }

  # --- Public API ---

  def init do
    unless :ets.whereis(@contact_table) != :undefined do
      :ets.new(@contact_table, [:named_table, :set, :public, read_concurrency: true])
    end

    case :ets.lookup(@contact_table, :state) do
      [] ->
        :ets.insert(@contact_table, {:state, %{
          submissions: %{},
          contributors: %{},
          completed: false,
          completed_at: nil,
          active: false
        }})
      _ -> :ok
    end

    :ok
  end

  @doc "Get the full Board Contact quest state."
  def state do
    case :ets.whereis(@contact_table) do
      :undefined -> %{submissions: %{}, contributors: %{}, completed: false, completed_at: nil, active: false}
      _ ->
        case :ets.lookup(@contact_table, :state) do
          [{:state, s}] -> s
          [] -> %{submissions: %{}, contributors: %{}, completed: false, completed_at: nil, active: false}
        end
    end
  end

  @doc "Get the requirements map."
  def requirements, do: @requirements

  @doc "Check if the quest is active."
  def active?, do: state().active

  @doc "Check if the quest is completed."
  def completed?, do: state().completed

  @doc "Activate the Board Contact quest (requires clearance level 8 from any player)."
  def activate do
    current = state()
    unless current.active or current.completed do
      :ets.insert(@contact_table, {:state, %{current | active: true}})
      Logger.info("Board Contact quest activated")
      :ok
    else
      :already_active
    end
  end

  @doc """
  Submit an item toward the Board Contact quest.
  Returns `:ok`, `{:completed, item_type}` if the quest finishes, or `:not_active`.
  """
  def submit_item(player_id, item_type) do
    current = state()

    cond do
      not current.active ->
        :not_active

      current.completed ->
        :already_completed

      not Map.has_key?(@requirements, item_type) ->
        :not_needed

      true ->
        current_count = Map.get(current.submissions, item_type, 0)
        required = Map.get(@requirements, item_type)

        if current_count >= required do
          :already_fulfilled
        else
          new_count = current_count + 1
          new_submissions = Map.put(current.submissions, item_type, new_count)

          # Track contributor
          player_contributions = Map.get(current.contributors, player_id, 0)
          new_contributors = Map.put(current.contributors, player_id, player_contributions + 1)

          new_state = %{current |
            submissions: new_submissions,
            contributors: new_contributors
          }

          # Check completion
          if quest_complete?(new_state) do
            new_state = %{new_state |
              completed: true,
              completed_at: System.system_time(:second)
            }
            :ets.insert(@contact_table, {:state, new_state})
            Logger.info("Board Contact quest COMPLETED!")
            {:completed, item_type}
          else
            :ets.insert(@contact_table, {:state, new_state})
            {:ok, item_type}
          end
        end
    end
  end

  @doc "Get progress summary for UI display."
  def progress_summary do
    current = state()

    requirements =
      Enum.map(@requirements, fn {item, required} ->
        submitted = Map.get(current.submissions, item, 0)
        %{
          item: item,
          required: required,
          submitted: submitted,
          complete: submitted >= required
        }
      end)

    total_required = @requirements |> Map.values() |> Enum.sum()
    total_submitted = current.submissions |> Map.values() |> Enum.sum()

    %{
      active: current.active,
      completed: current.completed,
      requirements: requirements,
      contributors: current.contributors,
      total_required: total_required,
      total_submitted: total_submitted,
      progress_pct: if(total_required > 0, do: trunc(total_submitted / total_required * 100), else: 0)
    }
  end

  @doc "Put state directly (for persistence)."
  def put_state(s) do
    :ets.insert(@contact_table, {:state, s})
  end

  @doc "Clear all state."
  def clear do
    if :ets.whereis(@contact_table) != :undefined do
      :ets.delete_all_objects(@contact_table)
    end
  end

  # --- Internal ---

  defp quest_complete?(st) do
    Enum.all?(@requirements, fn {item, required} ->
      Map.get(st.submissions, item, 0) >= required
    end)
  end
end
