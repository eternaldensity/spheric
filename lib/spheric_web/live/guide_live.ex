defmodule SphericWeb.GuideLive do
  use SphericWeb, :live_view

  @guide_root Path.expand("../../../docs/guide", __DIR__)

  # Slug → relative file path mapping for all guide pages
  @pages %{
    "home" => "Home.md",
    # Early Game
    "what-is-spheric" => "01-early-game/What Is Spheric.md",
    "your-first-session" => "01-early-game/Your First Session.md",
    "controls-camera" => "01-early-game/Controls & Camera.md",
    "the-hud" => "01-early-game/The HUD.md",
    "understanding-the-sphere" => "01-early-game/Understanding the Sphere.md",
    "your-starter-kit" => "01-early-game/Your Starter Kit.md",
    "placing-your-first-buildings" => "01-early-game/Placing Your First Buildings.md",
    "the-conveyor-network" => "01-early-game/The Conveyor Network.md",
    "extraction-processing" => "01-early-game/Extraction & Processing.md",
    "submitting-research" => "01-early-game/Submitting Research.md",
    "reaching-clearance-1" => "01-early-game/Reaching Clearance 1.md",
    "drone-fuel-drone-bay" => "01-early-game/Drone Fuel & the Drone Bay.md",
    "claiming-territory" => "01-early-game/Claiming Territory.md",
    "early-game-tips" => "01-early-game/Early Game Tips.md",
    # Mid Game
    "production-chains" => "02-mid-game/Production Chains.md",
    "the-fabricator" => "02-mid-game/The Fabricator.md",
    "the-distiller" => "02-mid-game/The Distiller.md",
    "advanced-logistics" => "02-mid-game/Advanced Logistics.md",
    "creatures-containment" => "02-mid-game/Creatures & Containment.md",
    "power-energy" => "02-mid-game/Power & Energy.md",
    "advanced-production" => "02-mid-game/Advanced Production.md",
    "trading-with-other-operators" => "02-mid-game/Trading with Other Operators.md",
    "the-hiss-corruption" => "02-mid-game/The Hiss & Corruption.md",
    "world-events" => "02-mid-game/World Events.md",
    "altered-items" => "02-mid-game/Altered Items.md",
    "mid-game-tips" => "02-mid-game/Mid Game Tips.md",
    # Late Game
    "high-tech-manufacturing" => "03-late-game/High-Tech Manufacturing.md",
    "nuclear-processing" => "03-late-game/Nuclear Processing.md",
    "paranatural-synthesis" => "03-late-game/Paranatural Synthesis.md",
    "endgame-buildings" => "03-late-game/Endgame Buildings.md",
    "the-board-interface" => "03-late-game/The Board Interface.md",
    "board-contact-quest" => "03-late-game/Board Contact Quest.md",
    "objects-of-power" => "03-late-game/Objects of Power.md",
    "late-game-tips" => "03-late-game/Late Game Tips.md",
    # Reference
    "controls-keybindings" => "reference/Controls & Keybindings.md",
    "recipe-reference" => "reference/Recipe Reference.md",
    "building-reference" => "reference/Building Reference.md",
    "creature-reference" => "reference/Creature Reference.md",
    "research-case-files" => "reference/Research Case Files.md",
    "biomes-resources" => "reference/Biomes & Resources.md",
    "altered-items-reference" => "reference/Altered Items Reference.md",
    "glossary" => "reference/Glossary.md",
    "server-setup-administration" => "reference/Server Setup & Administration.md"
  }

  # Reverse map: page title → slug (for wikilink resolution)
  @title_to_slug @pages
                 |> Enum.map(fn {slug, path} ->
                   title = path |> Path.basename(".md")
                   {title, slug}
                 end)
                 |> Map.new()

  # Sidebar navigation structure
  @nav [
    {"Getting Started", "hero-rocket-launch",
     [
       {"Home", "home"},
       {"What Is Spheric", "what-is-spheric"},
       {"Your First Session", "your-first-session"},
       {"Controls & Camera", "controls-camera"},
       {"The HUD", "the-hud"}
     ]},
    {"Early Game", "hero-play",
     [
       {"Understanding the Sphere", "understanding-the-sphere"},
       {"Your Starter Kit", "your-starter-kit"},
       {"Placing Your First Buildings", "placing-your-first-buildings"},
       {"The Conveyor Network", "the-conveyor-network"},
       {"Extraction & Processing", "extraction-processing"},
       {"Submitting Research", "submitting-research"},
       {"Reaching Clearance 1", "reaching-clearance-1"},
       {"Claiming Territory", "claiming-territory"},
       {"Early Game Tips", "early-game-tips"}
     ]},
    {"Mid Game", "hero-bolt",
     [
       {"Production Chains", "production-chains"},
       {"The Fabricator", "the-fabricator"},
       {"The Distiller", "the-distiller"},
       {"Advanced Logistics", "advanced-logistics"},
       {"Creatures & Containment", "creatures-containment"},
       {"Power & Energy", "power-energy"},
       {"Advanced Production", "advanced-production"},
       {"Trading with Other Operators", "trading-with-other-operators"},
       {"The Hiss & Corruption", "the-hiss-corruption"},
       {"World Events", "world-events"},
       {"Altered Items", "altered-items"},
       {"Mid Game Tips", "mid-game-tips"}
     ]},
    {"Late Game", "hero-fire",
     [
       {"High-Tech Manufacturing", "high-tech-manufacturing"},
       {"Nuclear Processing", "nuclear-processing"},
       {"Paranatural Synthesis", "paranatural-synthesis"},
       {"Endgame Buildings", "endgame-buildings"},
       {"The Board Interface", "the-board-interface"},
       {"Board Contact Quest", "board-contact-quest"},
       {"Objects of Power", "objects-of-power"},
       {"Late Game Tips", "late-game-tips"}
     ]},
    {"Reference", "hero-book-open",
     [
       {"Controls & Keybindings", "controls-keybindings"},
       {"Recipe Reference", "recipe-reference"},
       {"Building Reference", "building-reference"},
       {"Creature Reference", "creature-reference"},
       {"Research Case Files", "research-case-files"},
       {"Biomes & Resources", "biomes-resources"},
       {"Altered Items Reference", "altered-items-reference"},
       {"Glossary", "glossary"},
       {"Server Setup & Administration", "server-setup-administration"}
     ]}
  ]

  @impl true
  def mount(params, _session, socket) do
    page = Map.get(params, "page", "home")

    socket =
      socket
      |> assign(:page_title, "Guide")
      |> assign(:nav, @nav)
      |> load_page(page)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = Map.get(params, "page", "home")
    {:noreply, load_page(socket, page)}
  end

  defp load_page(socket, slug) do
    case Map.get(@pages, slug) do
      nil ->
        socket
        |> assign(:current_page, slug)
        |> assign(:content_html, "<h1>Page not found</h1><p>No guide page exists at this path.</p>")

      path ->
        full_path = Path.join(@guide_root, path)

        case File.read(full_path) do
          {:ok, markdown} ->
            html =
              markdown
              |> convert_wikilinks()
              |> convert_callouts()
              |> Earmark.as_html!(compact_output: true)

            title = path |> Path.basename(".md")

            socket
            |> assign(:current_page, slug)
            |> assign(:page_title, "#{title} — Guide")
            |> assign(:content_html, html)

          {:error, _} ->
            socket
            |> assign(:current_page, slug)
            |> assign(:content_html, "<h1>Error</h1><p>Could not read guide file.</p>")
        end
    end
  end

  # Convert Obsidian callout blocks into HTML divs before Earmark processes them.
  # Matches patterns like:
  #   > [!tip] Title
  #   > Content
  defp convert_callouts(markdown) do
    # Split into lines and process callout blocks
    markdown
    |> String.split("\n")
    |> process_callout_lines([])
    |> Enum.join("\n")
  end

  defp process_callout_lines([], acc), do: Enum.reverse(acc)

  defp process_callout_lines([line | rest], acc) do
    case Regex.run(~r/^>\s*\[!(\w+)\]\s*(.*)$/, line) do
      [_, type, title] ->
        {content_lines, remaining} = collect_callout_content(rest, [])
        alert_class = callout_class(type)
        title_str =
          if title != "",
            do: inline_markdown_to_html(title),
            else: String.capitalize(type)

        content =
          content_lines
          |> Enum.map(&inline_markdown_to_html/1)
          |> Enum.join("<br/>")

        html =
          "<div class=\"alert #{alert_class} my-4\">\n<div>\n<strong>#{title_str}</strong>\n<div>#{content}</div>\n</div>\n</div>"

        process_callout_lines(remaining, [html | acc])

      _ ->
        process_callout_lines(rest, [line | acc])
    end
  end

  defp collect_callout_content([line | rest], acc) do
    case Regex.run(~r/^>\s?(.*)$/, line) do
      [_, content] when content != "" ->
        collect_callout_content(rest, [content | acc])

      [_, ""] ->
        collect_callout_content(rest, acc)

      _ ->
        {Enum.reverse(acc), [line | rest]}
    end
  end

  defp collect_callout_content([], acc), do: {Enum.reverse(acc), []}

  # Convert inline markdown (links, bold, italic) to HTML for use inside raw HTML blocks
  defp inline_markdown_to_html(text) do
    text
    |> then(&Regex.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, &1, "<a href=\"\\2\">\\1</a>"))
    |> then(&Regex.replace(~r/\*\*([^*]+)\*\*/, &1, "<strong>\\1</strong>"))
    |> then(&Regex.replace(~r/\*([^*]+)\*/, &1, "<em>\\1</em>"))
  end

  defp callout_class(type) do
    case String.downcase(type) do
      t when t in ~w(tip success) -> "alert-success"
      t when t in ~w(warning important) -> "alert-warning"
      "danger" -> "alert-error"
      _ -> "alert-info"
    end
  end

  # Convert [[Wiki Links]] to standard markdown links.
  # Supports: [[Page]], [[Page|Display]], [[Page#Section]], [[Page#Section|Display]]
  defp convert_wikilinks(markdown) do
    Regex.replace(~r/\[\[([^\]]+)\]\]/, markdown, fn _, inner ->
      inner = String.replace(inner, "\\\\|", "|")

      {target, display} =
        case String.split(inner, "|", parts: 2) do
          [target, display] -> {target, display}
          [target] -> {target, target}
        end

      # Strip section anchor for slug lookup
      {page_part, anchor} =
        case String.split(target, "#", parts: 2) do
          [page, section] -> {page, "#" <> slugify_anchor(section)}
          [page] -> {page, ""}
        end

      slug = Map.get(@title_to_slug, page_part)

      if slug do
        "[#{display}](/guide/#{slug}#{anchor})"
      else
        "[#{display}](#)"
      end
    end)
  end

  defp slugify_anchor(section) do
    section
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .guide-prose .alert {
        border: 1px solid;
        color: inherit;
      }
      .guide-prose .alert-info {
        background: oklch(from var(--color-info) l c h / 0.12);
        border-color: oklch(from var(--color-info) l c h / 0.3);
      }
      .guide-prose .alert-success {
        background: oklch(from var(--color-success) l c h / 0.12);
        border-color: oklch(from var(--color-success) l c h / 0.3);
      }
      .guide-prose .alert-warning {
        background: oklch(from var(--color-warning) l c h / 0.12);
        border-color: oklch(from var(--color-warning) l c h / 0.3);
      }
      .guide-prose .alert-error {
        background: oklch(from var(--color-error) l c h / 0.12);
        border-color: oklch(from var(--color-error) l c h / 0.3);
      }
      .guide-prose table {
        border-collapse: collapse;
        width: 100%;
      }
      .guide-prose th,
      .guide-prose td {
        border: 1px solid var(--color-base-300);
        padding: 0.5rem 0.75rem;
      }
      .guide-prose th {
        background: var(--color-base-200);
        font-weight: 600;
      }
      .guide-prose tr:nth-child(even) {
        background: oklch(from var(--color-base-200) l c h / 0.4);
      }
    </style>
    <div style="margin: 0; background: var(--b1, #1d232a);" class="h-screen overflow-hidden">
      <div class="flex h-screen bg-base-100">
        <%!-- Sidebar --%>
        <aside class="w-72 shrink-0 bg-base-200 border-r border-base-300 overflow-y-auto h-screen">
          <div class="p-4 border-b border-base-300">
            <a href="/guide" class="text-xl font-bold flex items-center gap-2">
              <.icon name="hero-book-open" class="size-6" />
              Field Manual
            </a>
            <p class="text-xs opacity-60 mt-1">Operator's Guide to Spheric</p>
          </div>

          <nav class="p-2">
            <ul class="menu menu-sm w-full">
              <%= for {section, icon, pages} <- @nav do %>
                <li>
                  <details open={section_open?(pages, @current_page)}>
                    <summary class="font-semibold">
                      <.icon name={icon} class="size-4" />
                      {section}
                    </summary>
                    <ul>
                      <%= for {title, slug} <- pages do %>
                        <li>
                          <.link
                            navigate={~p"/guide/#{slug}"}
                            class={if slug == @current_page, do: "active", else: ""}
                          >
                            {title}
                          </.link>
                        </li>
                      <% end %>
                    </ul>
                  </details>
                </li>
              <% end %>
            </ul>
          </nav>

          <div class="p-4 border-t border-base-300 mt-auto">
            <a href="/" class="btn btn-ghost btn-sm w-full">
              <.icon name="hero-arrow-left" class="size-4" />
              Back to Game
            </a>
          </div>
        </aside>

        <%!-- Main content --%>
        <main class="flex-1 overflow-y-auto h-screen">
          <div class="max-w-4xl mx-auto p-8">
            <article class="prose prose-sm sm:prose-base max-w-none guide-prose">
              {raw(@content_html)}
            </article>
          </div>
        </main>
      </div>
    </div>
    """
  end

  defp section_open?(pages, current_page) do
    Enum.any?(pages, fn {_, slug} -> slug == current_page end)
  end
end
