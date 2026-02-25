defmodule Spheric.Game.Behaviors.PriorityMerger do
  @moduledoc """
  Priority merger building behavior.

  Accepts items from two side inputs with priority. The LEFT input
  always takes priority — the right input is only accepted when no
  item is pending from the left side.

  Input directions relative to orientation `d`:
    - Priority (left):  (d + 3) rem 4
    - Secondary (right): (d + 1) rem 4
  Output: orientation direction `d`
  """

  @doc "Returns the initial state for a newly placed priority merger."
  def initial_state do
    %{item: nil}
  end
end
