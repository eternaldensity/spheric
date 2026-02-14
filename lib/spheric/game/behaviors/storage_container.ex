defmodule Spheric.Game.Behaviors.StorageContainer do
  @moduledoc """
  Storage Container building behavior.

  Buffers up to 100 items of a single type. Accepts items from the rear
  and pushes them out the front (orientation direction). Once an item type
  is set, only accepts items of that same type until emptied.
  """

  @capacity 100

  @doc "Returns the initial state for a newly placed storage container."
  def initial_state do
    %{item_type: nil, count: 0, capacity: @capacity}
  end

  @doc "Returns the maximum capacity."
  def capacity, do: @capacity

  @doc """
  Try to accept an item into the container.
  Returns updated state if accepted, nil if rejected.
  """
  def try_accept_item(state, item_type) do
    cond do
      state.count >= state.capacity ->
        nil

      state.item_type == nil ->
        %{state | item_type: item_type, count: state.count + 1}

      state.item_type == item_type ->
        %{state | count: state.count + 1}

      true ->
        nil
    end
  end
end
