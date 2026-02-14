defmodule Spheric.Game.Behaviors.SubmissionTerminal do
  @moduledoc """
  Submission Terminal building behavior.

  Accepts items from conveyors in its input buffer. Each tick, if the input
  buffer has an item, submits it to the research system for the building's
  owner. The item is consumed (destroyed) — this is a sink building.

  State:
  - input_buffer: atom | nil — item waiting to be submitted
  - last_submitted: atom | nil — the last item type successfully submitted
  - total_submitted: integer — running total of items submitted
  """

  @doc "Returns the initial state for a newly placed submission terminal."
  def initial_state do
    %{input_buffer: nil, last_submitted: nil, total_submitted: 0}
  end

  @doc """
  Process one tick for a submission terminal. If there's an item in the
  input buffer, consume it and return the updated state with the item type
  for the caller to submit to research.

  Returns `{updated_building, consumed_item}` where consumed_item is
  the item atom or nil.
  """
  def tick(_key, building) do
    state = building.state

    case state.input_buffer do
      nil ->
        {building, nil}

      item ->
        new_state = %{
          state
          | input_buffer: nil,
            last_submitted: item,
            total_submitted: state.total_submitted + 1
        }

        {%{building | state: new_state}, item}
    end
  end
end
