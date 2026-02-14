defmodule Spheric.Game.Behaviors.TradeTerminal do
  @moduledoc """
  Trade Terminal building behavior.

  Enables async item exchange between players. Items fed into the terminal
  via conveyors are submitted to the active trade. When a trade completes,
  the received items appear in the output buffer for collection.

  State:
  - input_buffer: atom | nil — item waiting to be submitted to trade
  - output_buffer: atom | nil — item received from completed trade, ready for pickup
  - trade_id: integer | nil — the currently linked trade
  - total_sent: integer — running total of items sent
  - total_received: integer — running total of items received
  """

  alias Spheric.Game.Trading

  @doc "Returns the initial state for a newly placed trade terminal."
  def initial_state do
    %{
      input_buffer: nil,
      output_buffer: nil,
      trade_id: nil,
      total_sent: 0,
      total_received: 0
    }
  end

  @doc """
  Process one tick for a trade terminal. If there's an item in the
  input buffer and a trade is linked, submit the item to the trade.

  Returns `{updated_building, consumed_item}` where consumed_item is
  the item atom or nil.
  """
  def tick(_key, building) do
    state = building.state

    case {state.input_buffer, state.trade_id} do
      {nil, _} ->
        {building, nil}

      {_item, nil} ->
        # No trade linked — item stays in buffer
        {building, nil}

      {item, trade_id} ->
        case Trading.submit_item(trade_id, building.owner_id, item) do
          {:ok, _trade} ->
            new_state = %{state | input_buffer: nil, total_sent: state.total_sent + 1}
            {%{building | state: new_state}, item}

          {:completed, _trade} ->
            new_state = %{state | input_buffer: nil, total_sent: state.total_sent + 1}
            {%{building | state: new_state}, item}

          {:error, _reason} ->
            # Item not needed or trade not ready — keep item in buffer
            {building, nil}
        end
    end
  end
end
