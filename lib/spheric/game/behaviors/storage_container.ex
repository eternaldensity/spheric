defmodule Spheric.Game.Behaviors.StorageContainer do
  @moduledoc """
  Storage Container building behavior.

  Buffers up to 100 items of a single type. Accepts items from the rear
  and pushes them out the front (orientation direction). Once an item type
  is set, only accepts items of that same type until emptied.

  Items deposited by arms go into `inserted_count` (pending), which is not
  extractable until the next tick when `consolidate/1` merges them into
  `count` (stored). This prevents items from teleporting through a vault
  via chained arm transfers in a single tick.
  """

  @capacity 100

  @doc "Returns the initial state for a newly placed storage container."
  def initial_state do
    %{item_type: nil, count: 0, inserted_count: 0, capacity: @capacity}
  end

  @doc "Returns the maximum capacity."
  def capacity, do: @capacity

  @doc "Returns the total number of items (stored + pending insertion)."
  def total_count(state) do
    state.count + (state[:inserted_count] || 0)
  end

  @doc """
  Try to accept an item via arm transfer (goes to inserted_count, not
  extractable until consolidation). Returns updated state or nil.
  """
  def try_accept_item(state, item_type) do
    total = total_count(state)

    cond do
      total >= state.capacity ->
        nil

      state.item_type == nil ->
        %{state | item_type: item_type, inserted_count: (state[:inserted_count] || 0) + 1}

      state.item_type == item_type ->
        %{state | inserted_count: (state[:inserted_count] || 0) + 1}

      true ->
        nil
    end
  end

  @doc """
  Try to accept an item via conveyor push (goes directly to stored count,
  immediately extractable). Returns updated state or nil.
  """
  def try_accept_stored(state, item_type) do
    total = total_count(state)

    cond do
      total >= state.capacity ->
        nil

      state.item_type == nil ->
        %{state | item_type: item_type, count: state.count + 1}

      state.item_type == item_type ->
        %{state | count: state.count + 1}

      true ->
        nil
    end
  end

  @doc """
  Consolidate inserted items into stored. Called once per tick after all
  arm transfers are complete.
  """
  def consolidate(state) do
    inserted = state[:inserted_count] || 0

    if inserted > 0 do
      %{state | count: state.count + inserted, inserted_count: 0}
    else
      state
    end
  end
end
