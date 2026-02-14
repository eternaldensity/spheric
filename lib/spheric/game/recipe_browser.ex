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
    miner_recipes() ++ smelter_recipes() ++ refinery_recipes() ++ assembler_recipes()
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
      {:sulfur, :raw_sulfur}
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

  defp smelter_recipes do
    Behaviors.Smelter.recipes()
    |> Enum.map(fn {input, output} ->
      %{
        id: "smelter_#{input}",
        building: :smelter,
        building_name: Lore.display_name(:smelter),
        inputs: [%{item: input, name: Lore.display_name(input), count: 1}],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp refinery_recipes do
    Behaviors.Refinery.recipes()
    |> Enum.map(fn {input, output} ->
      %{
        id: "refinery_#{input}",
        building: :refinery,
        building_name: Lore.display_name(:refinery),
        inputs: [%{item: input, name: Lore.display_name(input), count: 1}],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp assembler_recipes do
    Behaviors.Assembler.recipes()
    |> Enum.map(fn {{input_a, input_b}, output} ->
      %{
        id: "assembler_#{input_a}_#{input_b}",
        building: :assembler,
        building_name: Lore.display_name(:assembler),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end
end
