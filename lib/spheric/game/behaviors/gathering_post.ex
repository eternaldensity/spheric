defmodule Spheric.Game.Behaviors.GatheringPost do
  @moduledoc """
  Gathering Post building behavior.

  Attracts nearby wild creatures that deposit biofuel.
  Free to place, max 3 per player. This is the bootstrap mechanism
  for the game's economy.
  """

  alias Spheric.Game.Creatures

  @attraction_radius 5
  @default_rate 20

  def initial_state do
    %{output_buffer: nil, progress: 0, rate: @default_rate, visitor_type: nil, powered: true}
  end

  @doc "Returns the attraction radius for gathering posts."
  def attraction_radius, do: @attraction_radius

  def tick(key, building) do
    state = building.state

    cond do
      state.output_buffer != nil ->
        building

      state.visitor_type != nil ->
        # Currently hosting a visitor, progress the visit
        if state.progress + 1 >= state.rate do
          %{building | state: %{state | output_buffer: :biofuel, progress: 0, visitor_type: nil}}
        else
          %{building | state: %{state | progress: state.progress + 1}}
        end

      true ->
        # Look for a nearby wild creature to visit
        case find_nearby_creature(key, building[:owner_id]) do
          nil ->
            building

          creature_type ->
            %{building | state: %{state | visitor_type: creature_type, progress: 0}}
        end
    end
  end

  defp find_nearby_creature({face, row, col} = key, owner_id) do
    area = Creatures.area_value(key, owner_id)
    radius = round(@attraction_radius * (1.0 + area))

    Creatures.all_wild_creatures()
    |> Enum.find_value(fn {_id, c} ->
      if c.face == face and
           abs(c.row - row) <= radius and
           abs(c.col - col) <= radius do
        c.type
      end
    end)
  end
end
