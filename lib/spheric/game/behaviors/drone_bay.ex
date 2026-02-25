defmodule Spheric.Game.Behaviors.DroneBay do
  @moduledoc """
  Drone Bay building behavior.

  A personal upgrade station for the player's camera drone.
  Operates as a state machine:
    - :idle — no upgrade selected, does not accept conveyor input
    - :accepting — an upgrade is selected, accepts specific items toward its cost
    - :complete — all items delivered, upgrade ready to apply

  When the auto_refuel upgrade is purchased, the bay also accepts
  biofuel/refined_fuel into a small internal buffer for auto-refuelling
  the drone when it flies nearby.
  """

  @fuel_buffer_max 5

  @upgrade_costs %{
    auto_refuel: %{iron_ingot: 5, copper_ingot: 3, wire: 2},
    expanded_tank: %{plate: 3, circuit: 2, wire: 4},
    drone_spotlight: %{iron_ingot: 4, wire: 3, copper_ingot: 2},
    expanded_cargo: %{plate: 5, circuit: 3, wire: 6}
  }

  def initial_state do
    %{
      mode: :idle,
      selected_upgrade: nil,
      required: %{},
      delivered: %{},
      fuel_buffer: [],
      auto_refuel_enabled: false,
      powered: true
    }
  end

  @doc "Returns the list of available upgrade atoms."
  def upgrades, do: Map.keys(@upgrade_costs)

  @doc "Returns the resource cost map for a given upgrade."
  def upgrade_cost(upgrade), do: Map.get(@upgrade_costs, upgrade, %{})

  @doc "Returns all upgrade costs (for UI display)."
  def all_upgrade_costs, do: @upgrade_costs

  @doc "Max fuel buffer size for auto-refuel."
  def fuel_buffer_max, do: @fuel_buffer_max

  @doc "Drone bay is passive — no autonomous production."
  def tick(_key, building), do: building

  @doc """
  Select an upgrade to install. Puts the bay into :accepting mode.
  Returns the updated state, or the original state if the upgrade
  is invalid or already purchased.
  """
  def select_upgrade(state, upgrade, player_upgrades) do
    if upgrade in upgrades() and not Map.get(player_upgrades, Atom.to_string(upgrade), false) do
      cost = upgrade_cost(upgrade)

      %{
        state
        | mode: :accepting,
          selected_upgrade: upgrade,
          required: cost,
          delivered: Map.new(cost, fn {k, _v} -> {k, 0} end)
      }
    else
      state
    end
  end

  @doc "Cancel the current upgrade selection. Returns to idle mode."
  def cancel_upgrade(state) do
    %{state | mode: :idle, selected_upgrade: nil, required: %{}, delivered: %{}}
  end

  @doc """
  Try to accept an item into the drone bay.
  Returns the updated state if accepted, or nil if rejected.
  """
  def try_accept_item(%{mode: :accepting, required: req, delivered: del} = state, item) do
    needed = Map.get(req, item, 0)
    have = Map.get(del, item, 0)

    if have < needed do
      new_del = Map.put(del, item, have + 1)
      new_state = %{state | delivered: new_del}

      if upgrade_complete?(new_state) do
        %{new_state | mode: :complete}
      else
        new_state
      end
    else
      nil
    end
  end

  def try_accept_item(
        %{mode: :idle, fuel_buffer: buf, auto_refuel_enabled: true} = state,
        item
      )
      when item in [:biofuel, :catalysed_fuel, :refined_fuel, :unstable_fuel, :stable_fuel] and length(buf) < @fuel_buffer_max do
    %{state | fuel_buffer: buf ++ [item]}
  end

  def try_accept_item(_state, _item), do: nil

  @doc "Returns true when the bay cannot accept any more input."
  def full?(%{mode: :accepting, required: req, delivered: del}) do
    Enum.all?(req, fn {item, needed} -> Map.get(del, item, 0) >= needed end)
  end

  def full?(%{mode: :idle, auto_refuel_enabled: true, fuel_buffer: buf}) do
    length(buf) >= @fuel_buffer_max
  end

  def full?(_state), do: true

  defp upgrade_complete?(%{required: req, delivered: del}) do
    Enum.all?(req, fn {item, needed} -> Map.get(del, item, 0) >= needed end)
  end
end
