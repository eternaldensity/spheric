defmodule Spheric.Game.Buildings do
  @moduledoc """
  Building type definitions and placement rules.

  Each building type has a display name and placement constraints.
  Miners require a resource tile; all others can be placed on any terrain.
  """

  @types [:conveyor, :miner, :smelter, :assembler, :splitter, :merger]

  @doc "Returns the list of all building type atoms."
  def types, do: @types

  @doc "Returns true if the given atom is a valid building type."
  def valid_type?(type), do: type in @types

  @doc "Returns the human-readable display name for a building type."
  def display_name(:conveyor), do: "Conveyor"
  def display_name(:miner), do: "Miner"
  def display_name(:smelter), do: "Smelter"
  def display_name(:assembler), do: "Assembler"
  def display_name(:splitter), do: "Splitter"
  def display_name(:merger), do: "Merger"

  @doc """
  Check if a building type can be placed on the given tile data.

  Miners require a resource deposit. All other types can go anywhere.
  """
  def can_place_on?(:miner, %{resource: nil}), do: false
  def can_place_on?(:miner, %{resource: {_type, amount}}) when amount > 0, do: true
  def can_place_on?(:miner, _tile), do: false
  def can_place_on?(type, _tile) when type in @types, do: true
  def can_place_on?(_type, _tile), do: false
end
