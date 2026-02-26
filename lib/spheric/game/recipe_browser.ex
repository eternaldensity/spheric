defmodule Spheric.Game.RecipeBrowser do
  @moduledoc """
  Centralized recipe browser.

  Aggregates all recipes from behavior modules into a searchable format
  for the recipe browser UI panel.
  """

  alias Spheric.Game.{Behaviors, Lore}

  @doc """
  Returns all recipes in a UI-friendly format.

  Each recipe is:
    %{
      id: string,
      building: atom,
      building_name: string,
      inputs: [%{item: atom, name: string, count: integer}],
      output: %{item: atom, name: string, count: integer}
    }
  """
  def all_recipes do
    miner_recipes() ++
      smelter_recipes() ++
      refinery_recipes() ++
      assembler_recipes() ++
      advanced_smelter_recipes() ++
      advanced_assembler_recipes() ++
      fabrication_plant_recipes() ++
      particle_collider_recipes() ++
      nuclear_refinery_recipes() ++
      paranatural_synthesizer_recipes() ++
      board_interface_recipes() ++
      recycler_recipes()
  end

  @doc """
  Search recipes by a query string. Matches against item names,
  building names, and lore display names (case insensitive).
  """
  def search(query) when is_binary(query) do
    q = String.downcase(query)

    all_recipes()
    |> Enum.filter(fn recipe ->
      matches_query?(recipe, q)
    end)
  end

  def search(_), do: all_recipes()

  @doc "Returns recipes for a specific building type atom."
  def for_building(building_type) when is_atom(building_type) do
    all_recipes()
    |> Enum.filter(fn recipe -> recipe.building == building_type end)
  end

  defp matches_query?(recipe, q) do
    fields = [
      recipe.building_name,
      recipe.output.name,
      Atom.to_string(recipe.building),
      Atom.to_string(recipe.output.item)
      | Enum.flat_map(recipe.inputs, fn i -> [i.name, Atom.to_string(i.item)] end)
    ]

    Enum.any?(fields, fn field ->
      String.contains?(String.downcase(field), q)
    end)
  end

  defp miner_recipes do
    [
      {:iron, :iron_ore},
      {:copper, :copper_ore},
      {:quartz, :raw_quartz},
      {:titanium, :titanium_ore},
      {:oil, :crude_oil},
      {:sulfur, :raw_sulfur},
      {:uranium, :raw_uranium}
    ]
    |> Enum.map(fn {resource, item} ->
      %{
        id: "miner_#{resource}",
        building: :miner,
        building_name: Lore.display_name(:miner),
        inputs: [%{item: resource, name: Lore.display_name(resource), count: 1}],
        output: %{item: item, name: Lore.display_name(item), count: 1}
      }
    end)
  end

  defp smelter_recipes, do: recipes_for(:smelter, Behaviors.Smelter)
  defp refinery_recipes, do: recipes_for(:refinery, Behaviors.Refinery)
  defp assembler_recipes, do: recipes_for(:assembler, Behaviors.Assembler)
  defp advanced_smelter_recipes, do: recipes_for(:advanced_smelter, Behaviors.AdvancedSmelter)
  defp advanced_assembler_recipes, do: recipes_for(:advanced_assembler, Behaviors.AdvancedAssembler)
  defp fabrication_plant_recipes, do: recipes_for(:fabrication_plant, Behaviors.FabricationPlant)
  defp particle_collider_recipes, do: recipes_for(:particle_collider, Behaviors.ParticleCollider)
  defp nuclear_refinery_recipes, do: recipes_for(:nuclear_refinery, Behaviors.NuclearRefinery)
  defp paranatural_synthesizer_recipes, do: recipes_for(:paranatural_synthesizer, Behaviors.ParanaturalSynthesizer)
  defp board_interface_recipes, do: recipes_for(:board_interface, Behaviors.BoardInterface)

  defp recycler_recipes do
    [
      %{
        id: "recycler_any",
        building: :recycler,
        building_name: Lore.display_name(:recycler),
        inputs: [%{item: :any, name: "Any Item", count: 10}],
        output: %{item: :random_resource, name: "Random Resource", count: 1}
      }
    ]
  end

  defp recipes_for(building_type, module) do
    module.recipes()
    |> Enum.map(fn %{inputs: inputs, output: {out_item, out_qty}} ->
      input_id = inputs |> Enum.map(fn {item, _qty} -> item end) |> Enum.join("_")

      %{
        id: "#{building_type}_#{input_id}",
        building: building_type,
        building_name: Lore.display_name(building_type),
        inputs:
          Enum.map(inputs, fn {item, qty} ->
            %{item: item, name: Lore.display_name(item), count: qty}
          end),
        output: %{item: out_item, name: Lore.display_name(out_item), count: out_qty}
      }
    end)
  end
end
