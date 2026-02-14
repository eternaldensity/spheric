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
  def display_name(:miner), do: "Extractor"
  def display_name(:smelter), do: "Processor"
  def display_name(:assembler), do: "Fabricator"
  def display_name(:refinery), do: "Distiller"
  def display_name(:splitter), do: "Distributor"
  def display_name(:merger), do: "Converger"
  def display_name(:submission_terminal), do: "Terminal"
  def display_name(:containment_trap), do: "Trap"
  def display_name(:purification_beacon), do: "Purification Beacon"
  def display_name(:defense_turret), do: "Defense Array"

  # Biomes
  def display_name(:grassland), do: "Threshold Plain"
  def display_name(:desert), do: "Arid Expanse"
  def display_name(:tundra), do: "Permafrost Zone"
  def display_name(:forest), do: "Overgrowth Sector"
  def display_name(:volcanic), do: "Astral Rift"

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
