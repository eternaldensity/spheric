defmodule Spheric.Game.Buildings do
  @moduledoc """
  Building type definitions and placement rules.

  Each building type has a display name and placement constraints.
  Miners require a resource tile; all others can be placed on any terrain.
  """

  @types [
    :conveyor,
    :conveyor_mk2,
    :conveyor_mk3,
    :miner,
    :smelter,
    :assembler,
    :refinery,
    :splitter,
    :merger,
    :balancer,
    :storage_container,
    :underground_conduit,
    :submission_terminal,
    :containment_trap,
    :purification_beacon,
    :defense_turret,
    :crossover,
    :claim_beacon,
    :trade_terminal
  ]

  @doc "Returns the list of all building type atoms."
  def types, do: @types

  @doc "Returns true if the given atom is a valid building type."
  def valid_type?(type), do: type in @types

  @doc "Returns the human-readable display name for a building type."
  def display_name(:conveyor), do: "Conveyor"
  def display_name(:conveyor_mk2), do: "Conveyor Mk2"
  def display_name(:conveyor_mk3), do: "Conveyor Mk3"
  def display_name(:miner), do: "Miner"
  def display_name(:smelter), do: "Smelter"
  def display_name(:assembler), do: "Assembler"
  def display_name(:refinery), do: "Refinery"
  def display_name(:splitter), do: "Splitter"
  def display_name(:merger), do: "Merger"
  def display_name(:balancer), do: "Balancer"
  def display_name(:storage_container), do: "Container"
  def display_name(:underground_conduit), do: "Conduit"
  def display_name(:crossover), do: "Crossover"
  def display_name(:submission_terminal), do: "Terminal"
  def display_name(:containment_trap), do: "Trap"
  def display_name(:purification_beacon), do: "Beacon"
  def display_name(:defense_turret), do: "Turret"
  def display_name(:claim_beacon), do: "Beacon"
  def display_name(:trade_terminal), do: "Trade"

  @doc """
  Check if a building type can be placed on the given tile data.

  Miners require a resource deposit. All other types can go anywhere.
  """
  def can_place_on?(:miner, %{resource: nil}), do: false
  def can_place_on?(:miner, %{resource: {_type, amount}}) when amount > 0, do: true
  def can_place_on?(:miner, _tile), do: false
  # Purification beacons and defense turrets can be placed on corrupted tiles
  def can_place_on?(type, _tile)
      when type in [:purification_beacon, :defense_turret] and type in @types,
      do: true

  def can_place_on?(type, _tile) when type in @types, do: true
  def can_place_on?(_type, _tile), do: false

  @doc "Returns the initial state map for a building of the given type."
  def initial_state(:miner), do: Spheric.Game.Behaviors.Miner.initial_state()
  def initial_state(:conveyor), do: Spheric.Game.Behaviors.Conveyor.initial_state()
  def initial_state(:conveyor_mk2), do: Spheric.Game.Behaviors.ConveyorMk2.initial_state()
  def initial_state(:conveyor_mk3), do: Spheric.Game.Behaviors.ConveyorMk3.initial_state()
  def initial_state(:smelter), do: Spheric.Game.Behaviors.Smelter.initial_state()
  def initial_state(:assembler), do: Spheric.Game.Behaviors.Assembler.initial_state()
  def initial_state(:refinery), do: Spheric.Game.Behaviors.Refinery.initial_state()
  def initial_state(:splitter), do: Spheric.Game.Behaviors.Splitter.initial_state()
  def initial_state(:merger), do: Spheric.Game.Behaviors.Merger.initial_state()
  def initial_state(:balancer), do: Spheric.Game.Behaviors.Balancer.initial_state()

  def initial_state(:storage_container),
    do: Spheric.Game.Behaviors.StorageContainer.initial_state()

  def initial_state(:underground_conduit),
    do: Spheric.Game.Behaviors.UndergroundConduit.initial_state()

  def initial_state(:crossover),
    do: Spheric.Game.Behaviors.Crossover.initial_state()

  def initial_state(:submission_terminal),
    do: Spheric.Game.Behaviors.SubmissionTerminal.initial_state()

  def initial_state(:containment_trap),
    do: Spheric.Game.Behaviors.ContainmentTrap.initial_state()

  def initial_state(:purification_beacon),
    do: Spheric.Game.Behaviors.PurificationBeacon.initial_state()

  def initial_state(:defense_turret),
    do: Spheric.Game.Behaviors.DefenseTurret.initial_state()

  def initial_state(:claim_beacon),
    do: Spheric.Game.Behaviors.ClaimBeacon.initial_state()

  def initial_state(:trade_terminal),
    do: Spheric.Game.Behaviors.TradeTerminal.initial_state()

  def initial_state(_type), do: %{}
end
