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
    :trade_terminal,
    :dimensional_stabilizer,
    :astral_projection_chamber,
    # New buildings
    :gathering_post,
    :essence_extractor,
    :bio_generator,
    :shadow_panel,
    :lamp,
    :substation,
    :transfer_station,
    :advanced_smelter,
    :advanced_assembler,
    :fabrication_plant,
    :particle_collider,
    :nuclear_refinery,
    :paranatural_synthesizer,
    :board_interface
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
  def display_name(:dimensional_stabilizer), do: "Stabilizer"
  def display_name(:astral_projection_chamber), do: "Projector"
  def display_name(:gathering_post), do: "Post"
  def display_name(:essence_extractor), do: "Extractor"
  def display_name(:bio_generator), do: "Generator"
  def display_name(:shadow_panel), do: "Shadow Panel"
  def display_name(:lamp), do: "Lamp"
  def display_name(:substation), do: "Substation"
  def display_name(:transfer_station), do: "Transfer"
  def display_name(:advanced_smelter), do: "Adv Smelter"
  def display_name(:advanced_assembler), do: "Adv Assembler"
  def display_name(:fabrication_plant), do: "Fab Plant"
  def display_name(:particle_collider), do: "Collider"
  def display_name(:nuclear_refinery), do: "Nuc Refinery"
  def display_name(:paranatural_synthesizer), do: "Synthesizer"
  def display_name(:board_interface), do: "Board"

  @doc """
  Check if a building type can be placed on the given tile data.

  Miners require a resource deposit. All other types can go anywhere.
  """
  def can_place_on?(:miner, %{resource: nil}), do: false
  def can_place_on?(:miner, %{resource: {_type, amount}}) when amount > 0, do: true
  def can_place_on?(:miner, _tile), do: false
  # Purification beacons, defense turrets, and dimensional stabilizers can be placed on corrupted tiles
  def can_place_on?(type, _tile)
      when type in [:purification_beacon, :defense_turret, :dimensional_stabilizer] and
             type in @types,
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

  def initial_state(:dimensional_stabilizer),
    do: Spheric.Game.Behaviors.DimensionalStabilizer.initial_state()

  def initial_state(:astral_projection_chamber),
    do: Spheric.Game.Behaviors.AstralProjectionChamber.initial_state()

  # New buildings
  def initial_state(:gathering_post),
    do: Spheric.Game.Behaviors.GatheringPost.initial_state()

  def initial_state(:essence_extractor),
    do: Spheric.Game.Behaviors.EssenceExtractor.initial_state()

  def initial_state(:bio_generator),
    do: Spheric.Game.Behaviors.BioGenerator.initial_state()

  def initial_state(:shadow_panel),
    do: Spheric.Game.Behaviors.ShadowPanel.initial_state()

  def initial_state(:lamp),
    do: Spheric.Game.Behaviors.Lamp.initial_state()

  def initial_state(:substation),
    do: Spheric.Game.Behaviors.Substation.initial_state()

  def initial_state(:transfer_station),
    do: Spheric.Game.Behaviors.TransferStation.initial_state()

  def initial_state(:advanced_smelter),
    do: Spheric.Game.Behaviors.AdvancedSmelter.initial_state()

  def initial_state(:advanced_assembler),
    do: Spheric.Game.Behaviors.AdvancedAssembler.initial_state()

  def initial_state(:fabrication_plant),
    do: Spheric.Game.Behaviors.FabricationPlant.initial_state()

  def initial_state(:particle_collider),
    do: Spheric.Game.Behaviors.ParticleCollider.initial_state()

  def initial_state(:nuclear_refinery),
    do: Spheric.Game.Behaviors.NuclearRefinery.initial_state()

  def initial_state(:paranatural_synthesizer),
    do: Spheric.Game.Behaviors.ParanaturalSynthesizer.initial_state()

  def initial_state(:board_interface),
    do: Spheric.Game.Behaviors.BoardInterface.initial_state()

  def initial_state(_type), do: %{}
end
