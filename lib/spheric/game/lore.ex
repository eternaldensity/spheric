defmodule Spheric.Game.Lore do
  @moduledoc """
  Federal Bureau of Control display name mappings.

  Internal atoms remain unchanged throughout the codebase.
  This module provides the thematic names shown to the player.
  """

  # Resources
  def display_name(:iron), do: "Ferric Compound"
  def display_name(:copper), do: "Paraelectric Ore"
  def display_name(:quartz), do: "Resonance Crystal"
  def display_name(:titanium), do: "Astral Ore"
  def display_name(:oil), do: "Black Rock Ichor"
  def display_name(:sulfur), do: "Threshold Dust"

  # Items (ores)
  def display_name(:iron_ore), do: "Ferric Compound (Raw)"
  def display_name(:copper_ore), do: "Paraelectric Ore (Raw)"
  def display_name(:raw_quartz), do: "Resonance Crystal (Raw)"
  def display_name(:titanium_ore), do: "Astral Ore (Raw)"
  def display_name(:crude_oil), do: "Black Rock Ichor (Crude)"
  def display_name(:raw_sulfur), do: "Threshold Dust (Raw)"

  # Items (processed)
  def display_name(:iron_ingot), do: "Ferric Standard"
  def display_name(:copper_ingot), do: "Paraelectric Bar"
  def display_name(:titanium_ingot), do: "Astral Ingot"
  def display_name(:polycarbonate), do: "Stabilized Polymer"
  def display_name(:sulfur_compound), do: "Threshold Compound"
  def display_name(:wire), do: "Conductive Filament"
  def display_name(:plate), do: "Structural Plate"
  def display_name(:circuit), do: "Resonance Circuit"
  def display_name(:frame), do: "Astral Frame"
  def display_name(:hiss_residue), do: "Hiss Residue"

  # Buildings
  def display_name(:conveyor), do: "Conduit"
  def display_name(:conveyor_mk2), do: "Conduit Mk-II"
  def display_name(:conveyor_mk3), do: "Conduit Mk-III"
  def display_name(:miner), do: "Extractor"
  def display_name(:smelter), do: "Processor"
  def display_name(:assembler), do: "Fabricator"
  def display_name(:refinery), do: "Distiller"
  def display_name(:splitter), do: "Distributor"
  def display_name(:merger), do: "Converger"
  def display_name(:balancer), do: "Load Equalizer"
  def display_name(:storage_container), do: "Containment Vault"
  def display_name(:underground_conduit), do: "Subsurface Link"
  def display_name(:crossover), do: "Transit Interchange"
  def display_name(:submission_terminal), do: "Terminal"
  def display_name(:containment_trap), do: "Trap"
  def display_name(:purification_beacon), do: "Purification Beacon"
  def display_name(:defense_turret), do: "Defense Array"
  def display_name(:claim_beacon), do: "Jurisdiction Beacon"
  def display_name(:trade_terminal), do: "Exchange Terminal"
  def display_name(:dimensional_stabilizer), do: "Dimensional Stabilizer"
  def display_name(:astral_projection_chamber), do: "Astral Projection Chamber"

  # Biomes
  def display_name(:grassland), do: "Threshold Plain"
  def display_name(:desert), do: "Arid Expanse"
  def display_name(:tundra), do: "Permafrost Zone"
  def display_name(:forest), do: "Overgrowth Sector"
  def display_name(:volcanic), do: "Astral Rift"

  # New resources
  def display_name(:uranium), do: "Threshold Radiant"
  def display_name(:raw_uranium), do: "Threshold Radiant (Raw)"
  def display_name(:enriched_uranium), do: "Enriched Radiant"
  def display_name(:quartz_crystal), do: "Refined Resonance Crystal"

  # New processed items
  def display_name(:motor), do: "Kinetic Driver"
  def display_name(:cable), do: "Shielded Conductor"
  def display_name(:reinforced_plate), do: "Reinforced Plate"
  def display_name(:heat_sink), do: "Thermal Regulator"
  def display_name(:heavy_frame), do: "Heavy Astral Frame"
  def display_name(:advanced_circuit), do: "Advanced Resonance Circuit"
  def display_name(:plastic_sheet), do: "Polymer Membrane"
  def display_name(:computer), do: "Computation Matrix"
  def display_name(:motor_housing), do: "Armored Drive Assembly"
  def display_name(:composite), do: "Structural Composite"
  def display_name(:supercomputer), do: "Hypercomputation Core"
  def display_name(:advanced_composite), do: "Paranatural Composite"
  def display_name(:nuclear_cell), do: "Radiant Cell"
  def display_name(:containment_module), do: "Anomaly Containment Module"
  def display_name(:dimensional_core), do: "Dimensional Core"
  def display_name(:astral_lens), do: "Astral Projection Lens"
  def display_name(:board_resonator), do: "Board Resonator"
  def display_name(:refined_fuel), do: "Refined Entity Fuel"

  # Creature items
  def display_name(:biofuel), do: "Entity Biofuel"
  def display_name(:creature_essence), do: "Anomalous Essence"

  # New buildings
  def display_name(:gathering_post), do: "Gathering Post"
  def display_name(:essence_extractor), do: "Essence Extractor"
  def display_name(:bio_generator), do: "Bio Generator"
  def display_name(:substation), do: "Substation"
  def display_name(:transfer_station), do: "Transfer Station"
  def display_name(:advanced_smelter), do: "Advanced Processor"
  def display_name(:advanced_assembler), do: "Advanced Fabricator"
  def display_name(:fabrication_plant), do: "Fabrication Plant"
  def display_name(:particle_collider), do: "Particle Collider"
  def display_name(:nuclear_refinery), do: "Nuclear Distiller"
  def display_name(:paranatural_synthesizer), do: "Paranatural Synthesizer"
  def display_name(:board_interface), do: "Board Interface"
  def display_name(:drone_bay), do: "Drone Bay"

  # New creatures
  def display_name(:flux_serpent), do: "Flux Serpent"
  def display_name(:resonance_moth), do: "Resonance Moth"
  def display_name(:iron_golem), do: "Ferric Sentinel"
  def display_name(:phase_wisp), do: "Phase Wisp"

  # Fallback
  def display_name(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  def display_name(str) when is_binary(str), do: str

  @doc "Convert a string key to its lore display name."
  def display_name_str(str) when is_binary(str) do
    case safe_to_atom(str) do
      nil -> str
      atom -> display_name(atom)
    end
  end

  defp safe_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end
end
