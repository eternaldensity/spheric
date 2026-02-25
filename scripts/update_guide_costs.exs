# scripts/update_guide_costs.exs
#
# Auto-updates the user guide markdown files with current costs, recipes, and
# research requirements from the game code.
#
# Sources of truth:
#   - Construction costs:  Spheric.Game.ConstructionCosts
#   - Display names:       Spheric.Game.Lore
#   - Recipes:             Spheric.Game.Behaviors.* (Production modules)
#   - Research:            Spheric.Game.Research
#   - Drone bay upgrades:  Spheric.Game.Behaviors.DroneBay
#
# Usage:
#   mix run scripts/update_guide_costs.exs           # update all guide files
#   mix run scripts/update_guide_costs.exs --dry-run  # preview changes only

alias Spheric.Game.{ConstructionCosts, Lore, Research}
alias Spheric.Game.Behaviors.{DroneBay, Loader, Unloader}

dry_run? = "--dry-run" in System.argv()

guide_dir = Path.join([File.cwd!(), "docs", "guide"])

# ── Helpers ──────────────────────────────────────────────────────────────────

defmodule GuideUpdater do
  @moduledoc false

  alias Spheric.Game.{ConstructionCosts, Lore}

  @doc "Format a cost map as a human-readable string: '3 Ferric Standard, 2 Paraelectric Bar'"
  def format_cost(cost_map) when is_map(cost_map) do
    cost_map
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.map(fn {item, qty} -> "#{qty} #{Lore.display_name(item)}" end)
    |> Enum.join(", ")
  end

  @doc "Format a cost map as a markdown table with Material | Quantity columns."
  def format_cost_table(cost_map) when is_map(cost_map) do
    rows =
      cost_map
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.map(fn {item, qty} ->
        "| #{Lore.display_name(item)} | #{qty} |"
      end)

    ["| Material | Quantity |", "|---|---|" | rows]
    |> Enum.join("\n")
  end

  @doc "Get the Bureau display name for a building type."
  def building_bureau_name(type), do: Lore.display_name(type)

  @doc "Get the common name for a building type."
  def building_common_name(type) do
    names = %{
      conveyor: "Conveyor", conveyor_mk2: "Conveyor Mk2", conveyor_mk3: "Conveyor Mk3",
      miner: "Miner", smelter: "Smelter", submission_terminal: "Submission Terminal",
      gathering_post: "Gathering Post", drone_bay: "Drone Bay",
      splitter: "Splitter", merger: "Merger", claim_beacon: "Claim Beacon",
      trade_terminal: "Trade Terminal", storage_container: "Storage Container",
      crossover: "Crossover", assembler: "Assembler", refinery: "Refinery",
      balancer: "Balancer", underground_conduit: "Underground Conduit",
      containment_trap: "Containment Trap", purification_beacon: "Purification Beacon",
      defense_turret: "Defense Turret", shadow_panel: "Shadow Panel", lamp: "Lamp",
      bio_generator: "Bio Generator", substation: "Substation",
      transfer_station: "Transfer Station", advanced_smelter: "Advanced Smelter",
      advanced_assembler: "Advanced Assembler", fabrication_plant: "Fabrication Plant",
      essence_extractor: "Essence Extractor",
      particle_collider: "Particle Collider", nuclear_refinery: "Nuclear Refinery",
      dimensional_stabilizer: "Dimensional Stabilizer",
      paranatural_synthesizer: "Paranatural Synthesizer",
      astral_projection_chamber: "Astral Projection Chamber",
      board_interface: "Board Interface",
      loader: "Loader", unloader: "Unloader",
      mixer: "Mixer"
    }
    Map.get(names, type, type |> Atom.to_string() |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" "))
  end

  @doc """
  Replace a section between two markers in a file's content.
  Markers are lines matching start_pattern and end_pattern (regexes).
  The replacement includes start line, new content, and end line.
  """
  def replace_section(content, start_pattern, end_pattern, new_section) do
    lines = String.split(content, "\n")

    {before, rest} = split_at_pattern(lines, start_pattern)
    {_old_section, after_section} = split_at_pattern(rest, end_pattern)

    case after_section do
      # end_pattern not found — leave file unchanged
      [] when rest == [] -> content
      _ ->
        new_lines = before ++ [new_section] ++ after_section
        Enum.join(new_lines, "\n")
    end
  end

  defp split_at_pattern(lines, pattern) do
    case Enum.find_index(lines, &Regex.match?(pattern, &1)) do
      nil -> {lines, []}
      idx -> Enum.split(lines, idx)
    end
  end

  # ── Building Reference generators ────────────────────────────────────────

  @doc "Generate a building reference table row."
  def building_row(type, notes) do
    bureau = building_bureau_name(type)
    common = building_common_name(type)
    tier = ConstructionCosts.tier(type)
    cost = case ConstructionCosts.cost(type) do
      nil -> "Free"
      cost_map -> format_cost(cost_map)
    end
    "| #{bureau} | #{common} | #{tier} | #{cost} | #{notes} |"
  end

  # ── Research case file generators ────────────────────────────────────────

  @doc "Format research requirements as a string."
  def format_requirements(requirements) do
    requirements
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.map(fn {item, qty} -> "#{qty} #{Lore.display_name(item)}" end)
    |> Enum.join(", ")
  end
end

# ── File update functions ──────────────────────────────────────────────────

write_file = fn path, content ->
  if dry_run? do
    IO.puts("  [DRY RUN] Would write #{Path.relative_to_cwd(path)}")
  else
    File.write!(path, content)
    IO.puts("  Updated #{Path.relative_to_cwd(path)}")
  end
end

read_file = fn path ->
  case File.read(path) do
    {:ok, content} -> content
    {:error, reason} ->
      IO.puts("  WARNING: Could not read #{path}: #{reason}")
      nil
  end
end

# Track which files were updated and which had no changes
updated_count = :counters.new(1, [:atomics])
skipped_count = :counters.new(1, [:atomics])

maybe_write = fn path, old_content, new_content ->
  if old_content == new_content do
    :counters.add(skipped_count, 1, 1)
  else
    write_file.(path, new_content)
    :counters.add(updated_count, 1, 1)
  end
end

IO.puts("=" |> String.duplicate(60))
IO.puts("  UPDATING GUIDE COSTS FROM GAME DATA")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# ═══════════════════════════════════════════════════════════════════════════
# 1. Building Reference
# ═══════════════════════════════════════════════════════════════════════════

IO.puts("── Building Reference ──")

building_ref_path = Path.join([guide_dir, "reference", "Building Reference.md"])
building_ref = read_file.(building_ref_path)

if building_ref do
  # Define the building categories with their notes
  logistics = [
    {:conveyor, "Basic item transport"},
    {:conveyor_mk2, "Faster transport"},
    {:conveyor_mk3, "Fastest transport"},
    {:splitter, "1 in → 3 out"},
    {:merger, "Many in → 1 out"},
    {:balancer, "1 in → 4 even out"},
    {:underground_conduit, "Tunnel under 1 tile"},
    {:crossover, "Cross paths"},
    {:transfer_station, "Bridge substations"},
    {:loader, "Vault → target (range 2)"},
    {:unloader, "Source → vault (range 2)"}
  ]

  production = [
    {:miner, "Resource extraction"},
    {:smelter, "Ore → ingot"},
    {:assembler, "Dual-input"},
    {:refinery, "Liquids/volatiles"},
    {:mixer, "Dual-input mixing"},
    {:advanced_smelter, "Fast + uranium"},
    {:advanced_assembler, "Advanced recipes"},
    {:fabrication_plant, "Triple-input"}
  ]

  advanced = [
    {:particle_collider, "Ultra-advanced"},
    {:nuclear_refinery, "Uranium enrichment"},
    {:paranatural_synthesizer, "Needs creature"},
    {:board_interface, "Final building"}
  ]

  power_energy = [
    {:bio_generator, "Burns fuel items"},
    {:shadow_panel, "Alt. power"},
    {:substation, "Radius 10 power"},
    {:lamp, "Decorative"},
    {:essence_extractor, "Creature essence"}
  ]

  storage_trade = [
    {:storage_container, "1 item type"},
    {:submission_terminal, "Research submissions"},
    {:trade_terminal, "Player trading"},
    {:gathering_post, "Attracts creatures (r7), produces biofuel"},
    {:drone_bay, "Permanent drone upgrades"}
  ]

  defense = [
    {:claim_beacon, "Radius 8 territory"},
    {:containment_trap, "Capture creatures (r3)"},
    {:defense_turret, "Auto-attacks Hiss (r3)"},
    {:purification_beacon, "Radius 5 anti-corruption"},
    {:dimensional_stabilizer, "Wide-area stability"},
    {:astral_projection_chamber, "Reveal creatures"}
  ]

  gen_table = fn buildings, _header ->
    rows = Enum.map(buildings, fn {type, notes} -> GuideUpdater.building_row(type, notes) end)
    header_line = "| Bureau Name | Common Name | Tier | Construction Cost | Notes |"
    separator = "|---|---|---|---|---|"
    [header_line, separator | rows] |> Enum.join("\n")
  end

  new_content = """
  # Building Reference

  Complete building list with Bureau names, clearance tiers, and construction costs.

  Construction costs are the resources you must deliver to a building's construction site before it becomes operational. [[Your Starter Kit|Starter Kit]] buildings skip construction entirely. See [[Placing Your First Buildings#Step 6 Construction|Construction]] for details.

  > [!warning] Contains all buildings including late-game spoilers.

  ---

  ## Logistics

  #{gen_table.(logistics, "Logistics")}

  See [[Advanced Logistics]] and [[The Conduit Network]] for usage guides.

  ---

  ## Production

  #{gen_table.(production, "Production")}

  See [[Extraction & Processing]], [[The Fabricator]], [[The Distiller]], [[Advanced Production]].

  ---

  ## Advanced

  #{gen_table.(advanced, "Advanced")}

  See [[High-Tech Manufacturing]], [[Paranatural Synthesis]], [[The Board Interface]].

  ---

  ## Power & Energy

  #{gen_table.(power_energy, "Power & Energy")}

  See [[Power & Energy]].

  ---

  ## Storage & Trade

  #{gen_table.(storage_trade, "Storage & Trade")}

  See [[Submitting Research]], [[Trading with Other Operators]], [[Creatures & Containment]], [[Drone Fuel & the Drone Bay]].

  ---

  ## Defense & Paranatural

  #{gen_table.(defense, "Defense & Paranatural")}

  See [[Claiming Territory]], [[Creatures & Containment]], [[The Hiss & Corruption]], [[Endgame Buildings]].

  ---

  **Back to:** [[Home]]
  """
  |> String.trim_leading()
  |> String.replace(~r/\n  /m, "\n")
  |> then(fn s -> s <> "\n" end)

  maybe_write.(building_ref_path, building_ref, new_content)
end

# ═══════════════════════════════════════════════════════════════════════════
# 2. Recipe Reference
# ═══════════════════════════════════════════════════════════════════════════

IO.puts("── Recipe Reference ──")

recipe_ref_path = Path.join([guide_dir, "reference", "Recipe Reference.md"])
recipe_ref = read_file.(recipe_ref_path)

if recipe_ref do
  # Read recipes from behavior modules
  format_input = fn item -> Lore.display_name(item) end

  smelter_recipes = [
    {[:iron_ore], :iron_ingot},
    {[:copper_ore], :copper_ingot},
    {[:titanium_ore], :titanium_ingot},
    {[:raw_quartz], :quartz_crystal}
  ]

  refinery_recipes = [
    {[:crude_oil], :polycarbonate},
    {[:raw_sulfur], :sulfur_compound},
    {[:biofuel], :refined_fuel}
  ]

  assembler_recipes = Spheric.Game.Behaviors.Assembler.recipes()
  mixer_recipes = Spheric.Game.Behaviors.Mixer.recipes()
  advanced_assembler_recipes = Spheric.Game.Behaviors.AdvancedAssembler.recipes()
  fabrication_plant_recipes = Spheric.Game.Behaviors.FabricationPlant.recipes()
  particle_collider_recipes = Spheric.Game.Behaviors.ParticleCollider.recipes()

  # Paranatural synthesizer recipes
  synth_recipes = Spheric.Game.Behaviors.ParanaturalSynthesizer.recipes()

  # Single-input recipe table
  single_table = fn recipes ->
    header = "| Input | Output |\n|---|---|"
    rows = Enum.map(recipes, fn {inputs, output} ->
      in_name = inputs |> List.first() |> format_input.()
      out_name = format_input.(output)
      "| #{in_name} | #{out_name} |"
    end)
    [header | rows] |> Enum.join("\n")
  end

  # Dual-input recipe table from Production macro recipes
  dual_table = fn recipes ->
    header = "| Input A | Input B | Output |\n|---|---|---|"
    rows = Enum.map(recipes, fn recipe ->
      inputs = recipe.inputs
      {out_type, _out_qty} = recipe.output
      # inputs is a keyword list like [copper_ingot: 1, copper_ingot: 1]
      input_names = Enum.map(inputs, fn {item, _qty} -> format_input.(item) end)
      case input_names do
        [a, b] -> "| #{a} | #{b} | #{format_input.(out_type)} |"
        [a] -> "| #{a} | — | #{format_input.(out_type)} |"
        _ -> "| #{Enum.join(input_names, " + ")} | #{format_input.(out_type)} |"
      end
    end)
    [header | rows] |> Enum.join("\n")
  end

  # Triple-input recipe table
  triple_table = fn recipes ->
    header = "| Input A | Input B | Input C | Output |\n|---|---|---|---|"
    rows = Enum.map(recipes, fn recipe ->
      inputs = recipe.inputs
      {out_type, _out_qty} = recipe.output
      input_names = Enum.map(inputs, fn {item, _qty} -> format_input.(item) end)
      case input_names do
        [a, b, c] -> "| #{a} | #{b} | #{c} | #{format_input.(out_type)} |"
        [a, b] -> "| #{a} | #{b} | — | #{format_input.(out_type)} |"
        _ -> "| #{Enum.join(input_names, " + ")} | | | #{format_input.(out_type)} |"
      end
    end)
    [header | rows] |> Enum.join("\n")
  end

  # Advanced smelter: same as smelter + extra recipes
  advanced_smelter_extra =
    Spheric.Game.Behaviors.AdvancedSmelter.recipes()
    |> Enum.reject(fn %{inputs: inputs} ->
      # Exclude the standard smelter recipes (single ore → ingot)
      case inputs do
        [{item, _qty}] -> item in [:iron_ore, :copper_ore, :titanium_ore, :raw_quartz]
        _ -> false
      end
    end)
    |> Enum.map(fn %{inputs: inputs, output: {out_type, _out_qty}} ->
      {Enum.map(inputs, fn {item, _qty} -> item end), out_type}
    end)

  # Nuclear refinery
  nuclear_refinery_recipes = [
    {[:raw_uranium], :enriched_uranium}
  ]

  new_content = """
  # Recipe Reference

  Complete production recipe tables for all buildings in Spheric.

  > [!warning] Contains recipes from all clearance levels, including late-game spoilers.

  ---

  ## Processor (Smelter) — 10 ticks

  *Available from start*

  #{single_table.(smelter_recipes)}

  ---

  ## Distiller (Refinery) — 12 ticks

  *Unlocked at Clearance 2. See [[The Distiller]].*

  #{single_table.(refinery_recipes)}

  ---

  ## Fabricator (Assembler) — 15 ticks

  *Unlocked at Clearance 1. See [[The Fabricator]].*

  #{dual_table.(assembler_recipes)}

  ---

  ## Compound Mixer (Mixer) — 15 ticks

  *Unlocked at Clearance 5. See [[Advanced Production]].*

  #{dual_table.(mixer_recipes)}

  ---

  ## Advanced Processor (Advanced Smelter) — 8 ticks

  *Unlocked at Clearance 4. See [[Advanced Production]].*

  All standard Processor recipes, plus:

  #{single_table.(advanced_smelter_extra)}

  ---

  ## Advanced Fabricator (Advanced Assembler) — 12 ticks

  *Unlocked at Clearance 5. See [[Advanced Production]].*

  #{dual_table.(advanced_assembler_recipes)}

  ---

  ## Fabrication Plant — 20 ticks

  *Unlocked at Clearance 5. See [[Advanced Production]].*

  #{triple_table.(fabrication_plant_recipes)}

  ---

  ## Particle Collider — 25 ticks

  *Unlocked at Clearance 6. See [[High-Tech Manufacturing]].*

  #{dual_table.(particle_collider_recipes)}

  ---

  ## Nuclear Distiller (Nuclear Refinery) — 20 ticks

  *Unlocked at Clearance 6. See [[High-Tech Manufacturing]].*

  #{single_table.(nuclear_refinery_recipes)}

  ---

  ## Paranatural Synthesizer — 30 ticks

  *Unlocked at Clearance 7. Requires assigned [[Creatures & Containment|creature]]. See [[Paranatural Synthesis]].*

  #{triple_table.(synth_recipes)}

  ---

  **Back to:** [[Home]]
  """
  |> String.trim_leading()
  |> String.replace(~r/\n  /m, "\n")
  |> then(fn s -> s <> "\n" end)

  maybe_write.(recipe_ref_path, recipe_ref, new_content)
end

# ═══════════════════════════════════════════════════════════════════════════
# 3. Research Case Files
# ═══════════════════════════════════════════════════════════════════════════

IO.puts("── Research Case Files ──")

research_path = Path.join([guide_dir, "reference", "Research Case Files.md"])
research_content = read_file.(research_path)

if research_content do
  case_files = Research.case_files()
  clearance_unlocks = %{
    1 => "Distributor, Converger, Jurisdiction Beacon, Exchange Terminal, Conduit Mk-II, Containment Vault, [[The Fabricator|Fabricator]], Drone Bay",
    2 => "[[The Distiller|Distiller]], Conduit Mk-III, Load Equalizer, Subsurface Link, Transit Interchange",
    3 => "[[Creatures & Containment|Trap]], Purification Beacon, Defense Array, Shadow Panel, Lamp",
    4 => "[[Power & Energy|Bio Generator, Substation]], Transfer Station, [[Advanced Logistics|Insertion Arm, Extraction Arm]], [[Advanced Production|Advanced Processor]]",
    5 => "[[Advanced Production|Compound Mixer, Advanced Fabricator, Fabrication Plant]], Essence Extractor",
    6 => "[[High-Tech Manufacturing|Particle Collider, Nuclear Distiller]]",
    7 => "[[Endgame Buildings|Dimensional Stabilizer, Astral Projection Chamber]], [[Paranatural Synthesis|Paranatural Synthesizer]]",
    8 => "[[The Board Interface]]"
  }

  clearance_names = %{
    1 => "Basic Logistics",
    2 => "Advanced Production",
    3 => "Research Clearance",
    4 => "Industrial Clearance",
    5 => "Heavy Industry",
    6 => "High-Tech",
    7 => "Paranatural",
    8 => "Board Access"
  }

  objects_of_power = %{
    1 => "Bureau Directive Alpha — +10% production speed",
    2 => "Pneumatic Transit Network — teleport between Terminals",
    3 => "Astral Projection — see all creature locations",
    4 => "Power Surge — +25% generator fuel duration",
    5 => "Logistics Mastery — all Conduits 20% faster",
    6 => "Altered Resonance — all [[Altered Items]] effects doubled",
    7 => "Entity Communion — +50% creature boost stacking",
    8 => "Board's Favor — corruption cannot seed within 10 tiles of buildings"
  }

  sections =
    for level <- 1..8 do
      level_files = Enum.filter(case_files, &(&1.clearance == level))

      rows = Enum.map(level_files, fn cf ->
        reqs = GuideUpdater.format_requirements(cf.requirements)
        "| #{cf.name} | #{reqs} |"
      end)

      table = ["| Case File | Requirements |", "|---|---|" | rows] |> Enum.join("\n")
      unlocks = Map.get(clearance_unlocks, level, "")
      name = Map.get(clearance_names, level, "Level #{level}")
      oop = Map.get(objects_of_power, level, "")

      """
      ## Clearance #{level} — #{name}

      #{table}

      **Unlocks:** #{unlocks}

      **#{if level == 1, do: "[[Objects of Power|Object of Power]]", else: "Object of Power"}:** #{oop}
      """
      |> String.trim()
    end

  new_content = """
  # Research Case Files

  Complete list of Bureau Case Files for all clearance levels, with requirements and unlocks.

  > [!warning] Contains research requirements and unlocks for all tiers, including late-game spoilers.

  See [[Submitting Research]] for how the research system works.

  ---

  #{Enum.join(sections, "\n\n---\n\n")}

  ---

  **Back to:** [[Home]]
  """
  |> String.trim_leading()
  |> String.replace(~r/\n  /m, "\n")
  |> then(fn s -> s <> "\n" end)

  maybe_write.(research_path, research_content, new_content)
end

# ═══════════════════════════════════════════════════════════════════════════
# 4. Inline cost references in guide pages
# ═══════════════════════════════════════════════════════════════════════════

IO.puts("── Inline cost references ──")

# Helper: replace a "Construction Cost" table (Material | Quantity format)
replace_cost_table = fn content, building_type ->
  cost = ConstructionCosts.cost(building_type)
  if cost do
    new_table = GuideUpdater.format_cost_table(cost)
    # Match table blocks that start with "| Material | Quantity |"
    Regex.replace(
      ~r/\| Material \| Quantity \|\n\|---\|---\|(\n\| .+ \| \d+ \|)+/,
      content,
      new_table
    )
  else
    content
  end
end

# For pages with a single building's cost table, replace it directly
single_cost_table_pages = [
  {"01-early-game/Claiming Territory.md", :claim_beacon},
  {"02-mid-game/The Fabricator.md", :assembler},
  {"02-mid-game/The Distiller.md", :refinery},
  {"02-mid-game/Trading with Other Operators.md", :trade_terminal},
]

for {rel_path, building_type} <- single_cost_table_pages do
  path = Path.join(guide_dir, rel_path)
  content = read_file.(path)
  if content do
    new_content = replace_cost_table.(content, building_type)
    maybe_write.(path, content, new_content)
  end
end

# ── Advanced Production (multiple **Cost:** lines) ──

adv_prod_path = Path.join(guide_dir, "02-mid-game/Advanced Production.md")
adv_prod = read_file.(adv_prod_path)

if adv_prod do
  # This file has multiple **Cost:** lines for different buildings.
  # We need to replace each one contextually.
  costs = %{
    mixer: ConstructionCosts.cost(:mixer),
    advanced_smelter: ConstructionCosts.cost(:advanced_smelter),
    advanced_assembler: ConstructionCosts.cost(:advanced_assembler),
    fabrication_plant: ConstructionCosts.cost(:fabrication_plant),
    essence_extractor: ConstructionCosts.cost(:essence_extractor)
  }

  # Split by sections and replace each cost line
  re_cost = fn content, section_re, cost_str ->
    Regex.replace(section_re, content, "\\1**Cost:** #{cost_str}")
  end

  new_content = adv_prod
  |> re_cost.(~r/(## Compound Mixer.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(costs.mixer))
  |> re_cost.(~r/(## Advanced Processor.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(costs.advanced_smelter))
  |> re_cost.(~r/(## Advanced Fabricator.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(costs.advanced_assembler))
  |> re_cost.(~r/(## Fabrication Plant.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(costs.fabrication_plant))
  |> re_cost.(~r/(## Essence Extractor.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(costs.essence_extractor))

  maybe_write.(adv_prod_path, adv_prod, new_content)
end

# ── Advanced Logistics (multiple **Cost:** lines and a conveyor table) ──

adv_log_path = Path.join(guide_dir, "02-mid-game/Advanced Logistics.md")
adv_log = read_file.(adv_log_path)

if adv_log do
  re_cost = fn content, section_re, cost_str ->
    Regex.replace(section_re, content, "\\1**Cost:** #{cost_str}")
  end

  new_content = adv_log
  |> re_cost.(~r/(## Distributor.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:splitter)))
  |> re_cost.(~r/(## Converger.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:merger)))
  |> re_cost.(~r/(## Load Equalizer.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:balancer)))
  |> re_cost.(~r/(## Subsurface Link.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:underground_conduit)))
  |> re_cost.(~r/(## Transit Interchange.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:crossover)))
  |> re_cost.(~r/(## Containment Vault.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:storage_container)))
  |> re_cost.(~r/(## Transfer Station.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:transfer_station)))
  |> re_cost.(~r/(## Insertion Arm.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:loader)))
  |> re_cost.(~r/(## Extraction Arm.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:unloader)))

  # Update arm Bulk Transfer upgrade costs
  loader_upgrade = GuideUpdater.format_cost(Loader.upgrade_cost(:stack_upgrade))
  unloader_upgrade = GuideUpdater.format_cost(Unloader.upgrade_cost(:stack_upgrade))
  upgrade_suffix = " — drop materials on the arm's tile, then click **Enable** in the tile info panel."

  new_content = Regex.replace(
    ~r/(## Insertion Arm.*?)\*\*Bulk Transfer Upgrade:\*\* [^\n]+/s,
    new_content,
    "\\1**Bulk Transfer Upgrade:** #{loader_upgrade}#{upgrade_suffix}"
  )
  new_content = Regex.replace(
    ~r/(## Extraction Arm.*?)\*\*Bulk Transfer Upgrade:\*\* [^\n]+/s,
    new_content,
    "\\1**Bulk Transfer Upgrade:** #{unloader_upgrade}#{upgrade_suffix}"
  )

  # Update conveyor tier table
  mk2_cost = GuideUpdater.format_cost(ConstructionCosts.cost(:conveyor_mk2))
  mk3_cost = GuideUpdater.format_cost(ConstructionCosts.cost(:conveyor_mk3))

  new_content = Regex.replace(
    ~r/\| Mk-II \| Conduit Mk-II \| Clearance 1 \| .+ \|/,
    new_content,
    "| Mk-II | Conduit Mk-II | Clearance 1 | #{mk2_cost} |"
  )
  new_content = Regex.replace(
    ~r/\| Mk-III \| Conduit Mk-III \| Clearance 2 \| .+ \|/,
    new_content,
    "| Mk-III | Conduit Mk-III | Clearance 2 | #{mk3_cost} |"
  )

  maybe_write.(adv_log_path, adv_log, new_content)
end

# ── Power & Energy ──

power_path = Path.join(guide_dir, "02-mid-game/Power & Energy.md")
power = read_file.(power_path)

if power do
  re_cost = fn content, section_re, cost_str ->
    Regex.replace(section_re, content, "\\1**Cost:** #{cost_str}")
  end

  new_content = power
  |> re_cost.(~r/(## Bio Generator.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:bio_generator)))
  |> re_cost.(~r/(## Substation.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:substation)))
  |> re_cost.(~r/(## Shadow Panel.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:shadow_panel)))

  maybe_write.(power_path, power, new_content)
end

# ── High-Tech Manufacturing ──

hitech_path = Path.join(guide_dir, "03-late-game/High-Tech Manufacturing.md")
hitech = read_file.(hitech_path)

if hitech do
  re_cost = fn content, section_re, cost_str ->
    Regex.replace(section_re, content, "\\1**Cost:** #{cost_str}")
  end

  new_content = hitech
  |> re_cost.(~r/(## Particle Collider.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:particle_collider)))
  |> re_cost.(~r/(## Nuclear Distiller.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:nuclear_refinery)))

  maybe_write.(hitech_path, hitech, new_content)
end

# ── The Hiss & Corruption ──

hiss_path = Path.join(guide_dir, "02-mid-game/The Hiss & Corruption.md")
hiss = read_file.(hiss_path)

if hiss do
  re_cost = fn content, section_re, cost_str ->
    Regex.replace(section_re, content, "\\1**Cost:** #{cost_str}")
  end

  new_content = hiss
  |> re_cost.(~r/(### Defense Array.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:defense_turret)))
  |> re_cost.(~r/(### Purification Beacon.*?)\*\*Cost:\*\* [^\n]+/s, GuideUpdater.format_cost(ConstructionCosts.cost(:purification_beacon)))

  maybe_write.(hiss_path, hiss, new_content)
end

# ── Endgame Buildings (cost tables) ──

endgame_path = Path.join(guide_dir, "03-late-game/Endgame Buildings.md")
endgame = read_file.(endgame_path)

if endgame do
  dim_stab_cost = GuideUpdater.format_cost_table(ConstructionCosts.cost(:dimensional_stabilizer))
  apc_cost = GuideUpdater.format_cost_table(ConstructionCosts.cost(:astral_projection_chamber))

  # Replace the first cost table (Dimensional Stabilizer)
  # and the second cost table (Astral Projection Chamber)
  # Split at sections
  parts = String.split(endgame, "## Astral Projection Chamber", parts: 2)

  new_content = case parts do
    [before_apc, apc_section] ->
      # Replace cost table in the Dimensional Stabilizer section
      updated_before = Regex.replace(
        ~r/\| Material \| Quantity \|\n\|---\|---\|(\n\| .+ \| \d+ \|)+/,
        before_apc,
        dim_stab_cost
      )
      # Replace cost table in the APC section
      updated_apc = Regex.replace(
        ~r/\| Material \| Quantity \|\n\|---\|---\|(\n\| .+ \| \d+ \|)+/,
        apc_section,
        apc_cost
      )
      updated_before <> "## Astral Projection Chamber" <> updated_apc
    _ -> endgame
  end

  maybe_write.(endgame_path, endgame, new_content)
end

# ── Paranatural Synthesis (cost table) ──

synth_path = Path.join(guide_dir, "03-late-game/Paranatural Synthesis.md")
synth = read_file.(synth_path)

if synth do
  synth_cost = GuideUpdater.format_cost_table(ConstructionCosts.cost(:paranatural_synthesizer))

  new_content = Regex.replace(
    ~r/\| Material \| Quantity \|\n\|---\|---\|(\n\| .+ \| \d+ \|)+/,
    synth,
    synth_cost
  )

  maybe_write.(synth_path, synth, new_content)
end

# ── The Board Interface (cost table + research requirements) ──

board_path = Path.join(guide_dir, "03-late-game/The Board Interface.md")
board = read_file.(board_path)

if board do
  board_cost = GuideUpdater.format_cost_table(ConstructionCosts.cost(:board_interface))

  new_content = Regex.replace(
    ~r/\| Material \| Quantity \|\n\|---\|---\|(\n\| .+ \| \d+ \|)+/,
    board,
    board_cost
  )

  # Update the clearance 8 case file requirements table
  l8_files = Research.case_files_for_level(8)
  l8_rows = Enum.map(l8_files, fn cf ->
    reqs = GuideUpdater.format_requirements(cf.requirements)
    "| #{cf.name} | #{reqs} |"
  end)
  l8_table = Enum.join(l8_rows, "\n")

  new_content = Regex.replace(
    ~r/\| Case File \| Requirement \|\n\|---\|---\|(\n\| .+ \| .+ \|)+/,
    new_content,
    "| Case File | Requirement |\n|---|---|\n#{l8_table}"
  )

  maybe_write.(board_path, board, new_content)
end

# ── Drone Fuel & the Drone Bay ──

drone_path = Path.join(guide_dir, "01-early-game/Drone Fuel & the Drone Bay.md")
drone = read_file.(drone_path)

if drone do
  # Update drone bay construction cost
  drone_bay_cost = GuideUpdater.format_cost(ConstructionCosts.cost(:drone_bay))
  new_content = Regex.replace(
    ~r/\*\*Construction Cost:\*\* .+/,
    drone,
    "**Construction Cost:** #{drone_bay_cost}"
  )

  # Update upgrade costs table
  upgrade_costs = DroneBay.all_upgrade_costs()

  auto_refuel = GuideUpdater.format_cost(upgrade_costs.auto_refuel)
  expanded_tank = GuideUpdater.format_cost(upgrade_costs.expanded_tank)
  drone_spotlight = GuideUpdater.format_cost(upgrade_costs.drone_spotlight)

  new_content = Regex.replace(
    ~r/\| \*\*Auto-Refuel\*\* \| .+ \|/,
    new_content,
    "| **Auto-Refuel** | #{auto_refuel} | Bay accepts biofuel into a buffer and auto-refuels your drone when you fly nearby |"
  )
  new_content = Regex.replace(
    ~r/\| \*\*Expanded Tank\*\* \| .+ \|/,
    new_content,
    "| **Expanded Tank** | #{expanded_tank} | Increases tank capacity from 5 to **10 slots** |"
  )
  new_content = Regex.replace(
    ~r/\| \*\*Drone Spotlight\*\* \| .+ \|/,
    new_content,
    "| **Drone Spotlight** | #{drone_spotlight} | Toggleable light (press **L**); burns fuel at **2x speed** while on |"
  )

  maybe_write.(drone_path, drone, new_content)
end

# ── Claiming Territory (inline mention) ──

claim_path = Path.join(guide_dir, "01-early-game/Claiming Territory.md")
claim = read_file.(claim_path)

if claim do
  beacon_cost = GuideUpdater.format_cost(ConstructionCosts.cost(:claim_beacon))
  new_content = Regex.replace(
    ~r/Beacons themselves require: .+/,
    claim,
    "Beacons themselves require: #{beacon_cost}"
  )
  maybe_write.(claim_path, claim, new_content)
end

# ── Placing Your First Buildings (miner cost example) ──

placing_path = Path.join(guide_dir, "01-early-game/Placing Your First Buildings.md")
placing = read_file.(placing_path)

if placing do
  miner_cost = ConstructionCosts.cost(:miner)
  total = miner_cost |> Map.values() |> Enum.sum()
  cost_str = GuideUpdater.format_cost(miner_cost)
  new_content = Regex.replace(
    ~r/Under construction \(0\/\d+\) — needs .+/,
    placing,
    "Under construction (0/#{total}) — needs #{cost_str}"
  )
  maybe_write.(placing_path, placing, new_content)
end

# ── Reaching Clearance 1 (L1 case file table) ──

reaching_path = Path.join(guide_dir, "01-early-game/Reaching Clearance 1.md")
reaching = read_file.(reaching_path)

if reaching do
  l1_files = Research.case_files_for_level(1)
  # Replace the case file table rows (keeping header)
  new_content = reaching
  for cf <- l1_files, reduce: new_content do
    acc ->
      Regex.replace(
        ~r/\| #{Regex.escape(cf.name)} \| .+ \|/,
        acc,
        "| #{cf.name} | #{GuideUpdater.format_requirements(cf.requirements)} |"
      )
  end
  |> then(fn new_content -> maybe_write.(reaching_path, reaching, new_content) end)
end

# ── Early Game Tips (L1 requirement mentions) ──

tips_path = Path.join(guide_dir, "01-early-game/Early Game Tips.md")
tips = read_file.(tips_path)

if tips do
  l1_files = Research.case_files_for_level(1)
  iron_req = Enum.find(l1_files, fn cf -> cf.id == "l1_iron_delivery" end)
  copper_req = Enum.find(l1_files, fn cf -> cf.id == "l1_copper_delivery" end)

  if iron_req && copper_req do
    iron_qty = iron_req.requirements[:iron_ingot]
    copper_qty = copper_req.requirements[:copper_ingot]

    new_content = Regex.replace(
      ~r/\*\*\d+ Ferric Standards\*\* and \*\*\d+ Paraelectric Bars\*\*/,
      tips,
      "**#{iron_qty} Ferric Standards** and **#{copper_qty} Paraelectric Bars**"
    )
    maybe_write.(tips_path, tips, new_content)
  end
end

# ── Submitting Research (L1 requirement mentions) ──

submit_path = Path.join(guide_dir, "01-early-game/Submitting Research.md")
submit = read_file.(submit_path)

if submit do
  l1_files = Research.case_files_for_level(1)
  iron_req = Enum.find(l1_files, fn cf -> cf.id == "l1_iron_delivery" end)
  copper_req = Enum.find(l1_files, fn cf -> cf.id == "l1_copper_delivery" end)

  if iron_req && copper_req do
    iron_qty = iron_req.requirements[:iron_ingot]
    copper_qty = copper_req.requirements[:copper_ingot]

    new_content =
      Regex.replace(~r/\*\*\d+ Ferric Standards\*\*/, submit, "**#{iron_qty} Ferric Standards**")
      |> then(&Regex.replace(~r/\*\*\d+ Paraelectric Bars\*\*/, &1, "**#{copper_qty} Paraelectric Bars**"))

    maybe_write.(submit_path, submit, new_content)
  end
end

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════

IO.puts("")
IO.puts("=" |> String.duplicate(60))
updated = :counters.get(updated_count, 1)
skipped = :counters.get(skipped_count, 1)
IO.puts("  Done. #{updated} file(s) updated, #{skipped} file(s) unchanged.")
if dry_run?, do: IO.puts("  (Dry run — no files were actually modified.)")
IO.puts("=" |> String.duplicate(60))
