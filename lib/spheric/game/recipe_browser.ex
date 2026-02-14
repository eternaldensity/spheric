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
      board_interface_recipes()
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

  defp advanced_smelter_recipes do
    Behaviors.AdvancedSmelter.recipes()
    |> Enum.map(fn {input, output} ->
      %{
        id: "advanced_smelter_#{input}",
        building: :advanced_smelter,
        building_name: Lore.display_name(:advanced_smelter),
        inputs: [%{item: input, name: Lore.display_name(input), count: 1}],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp advanced_assembler_recipes do
    Behaviors.AdvancedAssembler.recipes()
    |> Enum.map(fn {{input_a, input_b}, output} ->
      %{
        id: "advanced_assembler_#{input_a}_#{input_b}",
        building: :advanced_assembler,
        building_name: Lore.display_name(:advanced_assembler),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp fabrication_plant_recipes do
    Behaviors.FabricationPlant.recipes()
    |> Enum.map(fn {{input_a, input_b, input_c}, output} ->
      %{
        id: "fabrication_plant_#{input_a}_#{input_b}_#{input_c}",
        building: :fabrication_plant,
        building_name: Lore.display_name(:fabrication_plant),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1},
          %{item: input_c, name: Lore.display_name(input_c), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp particle_collider_recipes do
    Behaviors.ParticleCollider.recipes()
    |> Enum.map(fn {{input_a, input_b}, output} ->
      %{
        id: "particle_collider_#{input_a}_#{input_b}",
        building: :particle_collider,
        building_name: Lore.display_name(:particle_collider),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp nuclear_refinery_recipes do
    Behaviors.NuclearRefinery.recipes()
    |> Enum.map(fn {input, output} ->
      %{
        id: "nuclear_refinery_#{input}",
        building: :nuclear_refinery,
        building_name: Lore.display_name(:nuclear_refinery),
        inputs: [%{item: input, name: Lore.display_name(input), count: 1}],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp paranatural_synthesizer_recipes do
    Behaviors.ParanaturalSynthesizer.recipes()
    |> Enum.map(fn {{input_a, input_b, input_c}, output} ->
      %{
        id: "paranatural_synthesizer_#{input_a}_#{input_b}_#{input_c}",
        building: :paranatural_synthesizer,
        building_name: Lore.display_name(:paranatural_synthesizer),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1},
          %{item: input_c, name: Lore.display_name(input_c), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end

  defp board_interface_recipes do
    Behaviors.BoardInterface.recipes()
    |> Enum.map(fn {{input_a, input_b, input_c}, output} ->
      %{
        id: "board_interface_#{input_a}_#{input_b}_#{input_c}",
        building: :board_interface,
        building_name: Lore.display_name(:board_interface),
        inputs: [
          %{item: input_a, name: Lore.display_name(input_a), count: 1},
          %{item: input_b, name: Lore.display_name(input_b), count: 1},
          %{item: input_c, name: Lore.display_name(input_c), count: 1}
        ],
        output: %{item: output, name: Lore.display_name(output), count: 1}
      }
    end)
  end
end
