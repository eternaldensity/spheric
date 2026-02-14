defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT
  alias Spheric.Geometry.Coordinate

  alias Spheric.Game.{
    WorldServer,
    WorldStore,
    Buildings,
    Persistence,
    Research,
    Creatures,
    Lore,
    AlteredItems,
    ObjectsOfPower,
    Hiss,
    Territory,
    Trading,
    RecipeBrowser,
    Statistics,
    WorldEvents,
    TheBoard,
    BoardContact,
    ShiftCycle
  }

  alias SphericWeb.Presence

  require Logger

  @presence_topic "game:presence"

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()

    # Build initial buildings snapshot
    buildings_data = build_buildings_snapshot()

    # Initial face set: all faces (until first camera_update narrows it)
    initial_faces = MapSet.new(0..29)

    # Subscribe to face PubSub topics and presence
    if connected?(socket) do
      for face_id <- MapSet.to_list(initial_faces) do
        Phoenix.PubSub.subscribe(Spheric.PubSub, "world:face:#{face_id}")
      end

      Phoenix.PubSub.subscribe(Spheric.PubSub, @presence_topic)
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:admin")
    end

    # Restore player identity and camera from client localStorage (via connect params),
    # or generate fresh values for new players.
    {player_id, player_name, player_color, camera} =
      if connected?(socket) do
        restore_player(get_connect_params(socket))
      else
        {"player:temp", Presence.random_name(), Presence.random_color(),
         %{x: 0.0, y: 0.0, z: 3.5, tx: 0.0, ty: 0.0, tz: 0.0}}
      end

    # Persist player identity mapping (id -> name, color)
    if connected?(socket), do: Persistence.upsert_player(player_id, player_name, player_color)

    # Load research unlocks and subscribe to research updates
    world_id =
      if connected?(socket) do
        case Spheric.Repo.get_by(Spheric.Game.Schema.World, name: "default") do
          nil -> nil
          world -> world.id
        end
      end

    if connected?(socket) and world_id do
      Research.load_player_unlocks(world_id, player_id)
      Phoenix.PubSub.subscribe(Spheric.PubSub, "research:#{player_id}")
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:events")
    end

    # Track presence (only when connected)
    if connected?(socket) do
      Presence.track(self(), @presence_topic, player_id, %{
        name: player_name,
        color: player_color,
        camera: %{x: camera.x, y: camera.y, z: camera.z}
      })
    end

    unlocked = if world_id, do: Research.unlocked_buildings(player_id), else: Buildings.types()
    research_summary = if world_id, do: Research.progress_summary(world_id, player_id), else: []
    clearance = if world_id, do: Research.clearance_level(player_id), else: 0

    socket =
      socket
      |> assign(:page_title, "Spheric")
      |> assign(:geometry_data, geometry_data)
      |> assign(:selected_tile, nil)
      |> assign(:tile_info, nil)
      |> assign(:selected_building_type, nil)
      |> assign(:placement_orientation, 0)
      |> assign(:camera_pos, {camera.x, camera.y, camera.z})
      |> assign(:visible_faces, initial_faces)
      |> assign(:subscribed_faces, initial_faces)
      |> assign(:building_types, unlocked)
      |> assign(:line_mode, false)
      |> assign(:player_id, player_id)
      |> assign(:player_name, player_name)
      |> assign(:player_color, player_color)
      |> assign(:world_id, world_id)
      |> assign(:show_research, false)
      |> assign(:research_summary, research_summary)
      |> assign(:clearance_level, clearance)
      |> assign(:show_creatures, false)
      |> assign(:creature_roster, Creatures.get_player_roster(player_id))
      |> assign(:objects_of_power, ObjectsOfPower.player_objects(player_id))
      |> assign(:show_trading, false)
      |> assign(:open_trades, [])
      |> assign(:my_trades, [])
      |> assign(:trade_form, %{offered: %{}, requested: %{}})
      |> assign(:show_recipes, false)
      |> assign(:recipe_search, "")
      |> assign(:recipes, RecipeBrowser.all_recipes())
      |> assign(:show_stats, false)
      |> assign(:stats_summary, [])
      |> assign(:blueprint_mode, nil)
      |> assign(:blueprint_count, 0)
      |> assign(:board_message, nil)
      |> assign(:active_event, WorldEvents.active_event())
      |> assign(:shift_phase, ShiftCycle.current_phase())
      |> assign(:show_board_contact, false)
      |> assign(:board_contact, BoardContact.progress_summary())
      |> push_event("buildings_snapshot", %{buildings: buildings_data})

    # Tell the client to restore camera and persist any newly-generated identity
    socket =
      if connected?(socket) do
        socket =
          push_event(socket, "restore_player", %{
            player_id: player_id,
            player_name: player_name,
            player_color: player_color,
            camera: camera
          })

        # Stream terrain data per-face via push_event (too large for data-attribute at 64x64)
        send(self(), :send_terrain)

        # Send initial shift cycle lighting
        lighting = ShiftCycle.current_lighting()

        socket =
          push_event(socket, "shift_cycle_changed", %{
            phase: Atom.to_string(ShiftCycle.current_phase()),
            ambient: lighting.ambient,
            directional: lighting.directional,
            intensity: lighting.intensity,
            bg: lighting.bg
          })

        socket
      else
        socket
      end

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="game-container"
      phx-hook="GameRenderer"
      phx-update="ignore"
      phx-window-keydown="keydown"
      data-geometry={Jason.encode!(@geometry_data)}
      style="width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0;"
    >
    </div>

    <%!-- === PLAYER INFO (top-right) === --%>
    <div
      id="player-info"
      style="position: fixed; top: 16px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 6px 12px; border: 1px solid var(--fbc-border); font-family: 'Courier New', monospace; font-size: 12px; pointer-events: none; display: flex; align-items: center; gap: 6px; text-transform: uppercase; letter-spacing: 0.05em;"
    >
      <span style={"display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #{@player_color};"}>
      </span>
      {@player_name}
    </div>

    <%!-- === TILE INFO (top-left) === --%>
    <div
      :if={@tile_info}
      style="position: fixed; top: 16px; left: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 10px 14px; border: 1px solid var(--fbc-border); font-family: 'Courier New', monospace; font-size: 13px; line-height: 1.6; pointer-events: auto; min-width: 200px;"
    >
      <div style="color: var(--fbc-text-dim); font-size: 10px; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.1em;">
        Sector {@tile_info.face} &middot; {@tile_info.row},{@tile_info.col}
      </div>
      <div>
        Terrain:
        <span style="color: var(--fbc-info);">{Lore.display_name_str(@tile_info.terrain)}</span>
      </div>
      <div :if={@tile_info.resource}>
        Resource:
        <span style="color: var(--fbc-highlight);">
          {Lore.display_name_str(@tile_info.resource_type)}
        </span>
        <span style="color: var(--fbc-text-dim);">({@tile_info.resource_amount})</span>
      </div>
      <div :if={@tile_info.resource == nil} style="color: var(--fbc-text-dim);">
        No deposits detected
      </div>
      <div
        :if={@tile_info[:altered_item]}
        style="margin-top: 4px; border-top: 1px solid var(--fbc-accent-dim); padding-top: 4px;"
      >
        <div style="color: var(--fbc-accent); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em;">
          Altered Item
        </div>
        <div style="color: var(--fbc-gold);">{@tile_info.altered_item.name}</div>
        <div style="color: var(--fbc-text-dim); font-size: 11px;">
          {@tile_info.altered_item.description}
        </div>
      </div>
      <div
        :if={@tile_info[:corruption] && @tile_info.corruption > 0}
        style="margin-top: 4px; border-top: 1px solid #882222; padding-top: 4px;"
      >
        <div style="color: #ff4444; font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; animation: pulse 2s ease-in-out infinite;">
          Hiss Corruption
        </div>
        <div style="color: #ff6666; font-size: 12px;">
          Intensity: {@tile_info.corruption}/10
        </div>
        <div style="background: #331111; height: 4px; margin-top: 2px;">
          <div style={"background: #ff2222; height: 4px; width: #{@tile_info.corruption * 10}%;"}>
          </div>
        </div>
      </div>
      <div
        :if={@tile_info[:territory]}
        style="margin-top: 4px; border-top: 1px solid #226633; padding-top: 4px;"
      >
        <div style="color: #44cc66; font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em;">
          Jurisdiction Zone
        </div>
        <div style="color: #66dd88; font-size: 11px;">
          Operator: {@tile_info.territory.owner_name}
        </div>
      </div>
      <div
        :if={@tile_info.building}
        style="margin-top: 4px; border-top: 1px solid var(--fbc-border); padding-top: 4px;"
      >
        <div style="display: flex; align-items: center; gap: 6px;">
          <span style="color: var(--fbc-accent); font-size: 9px; text-transform: uppercase; letter-spacing: 0.1em;">
            CLASSIFIED
          </span>
          <span style="color: var(--fbc-highlight);">{@tile_info.building_name}</span>
        </div>
        <div style="color: var(--fbc-text-dim); font-size: 11px;">
          Facing: {direction_label(@tile_info.building_orientation)}
        </div>
        <div :if={@tile_info.building_status} style="color: var(--fbc-text-dim); font-size: 11px;">
          {@tile_info.building_status}
        </div>
        <div :if={@tile_info.building_owner_name} style="color: var(--fbc-text-dim); font-size: 11px;">
          Operator: <span style="color: var(--fbc-info);">{@tile_info.building_owner_name}</span>
        </div>
        <button
          :if={@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id}
          phx-click="remove_building"
          phx-value-face={@tile_info.face}
          phx-value-row={@tile_info.row}
          phx-value-col={@tile_info.col}
          style="margin-top: 6px; padding: 4px 10px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.2); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em;"
        >
          Decommission
        </button>
      </div>
      <div :if={@tile_info.building == nil} style="color: var(--fbc-text-dim); margin-top: 4px;">
        No structure
      </div>
    </div>

    <%!-- === CASE FILES / RESEARCH PANEL (top-right) === --%>
    <div
      :if={@show_research}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 280px; max-width: 340px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-border);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
          Case Files
        </span>
        <span style="font-size: 10px; color: var(--fbc-accent); text-transform: uppercase; letter-spacing: 0.1em; border: 1px solid var(--fbc-accent-dim); padding: 2px 6px;">
          Clearance L{@clearance_level}
        </span>
      </div>
      <div
        :for={cf <- @research_summary}
        style={"margin-bottom: 10px; padding: 8px; border: 1px solid #{if cf.completed, do: "var(--fbc-success)", else: "var(--fbc-border)"}; background: #{if cf.completed, do: "rgba(102,136,68,0.08)", else: "rgba(255,255,255,0.02)"};"}
      >
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style={"color: #{if cf.completed, do: "var(--fbc-success)", else: "var(--fbc-cream)"}; font-size: 12px;"}>
            {cf.name}
          </span>
          <span style={"font-size: 9px; text-transform: uppercase; letter-spacing: 0.1em; color: #{if cf.completed, do: "var(--fbc-success)", else: "var(--fbc-text-dim)"};"}>
            {if cf.completed, do: "APPROVED", else: "L#{cf.clearance}"}
          </span>
        </div>
        <div style="color: var(--fbc-text-dim); font-size: 10px; margin-top: 2px;">
          {cf.description}
        </div>
        <div :for={req <- cf.requirements} style="margin-top: 4px; font-size: 11px;">
          <span style={"color: #{if req.submitted >= req.required, do: "var(--fbc-success)", else: "var(--fbc-highlight)"};"}>
            {Lore.display_name(req.item)}
          </span>
          <span style="color: var(--fbc-text-dim);">
            {req.submitted}/{req.required}
          </span>
          <div style="background: var(--fbc-border); height: 3px; margin-top: 2px;">
            <div style={"background: #{if req.submitted >= req.required, do: "var(--fbc-success)", else: "var(--fbc-accent)"}; height: 3px; width: #{min(100, trunc(req.submitted / max(req.required, 1) * 100))}%;"}>
            </div>
          </div>
        </div>
      </div>
      <%!-- Objects of Power section --%>
      <div
        :if={@objects_of_power != []}
        style="margin-top: 12px; border-top: 1px solid var(--fbc-border); padding-top: 10px;"
      >
        <div style="font-size: 11px; color: var(--fbc-gold); text-transform: uppercase; letter-spacing: 0.15em; margin-bottom: 8px;">
          Objects of Power
        </div>
        <div
          :for={obj <- @objects_of_power}
          style="margin-bottom: 6px; padding: 6px 8px; border: 1px solid var(--fbc-gold); background: rgba(204,170,68,0.08);"
        >
          <div style="color: var(--fbc-gold); font-size: 11px;">{obj.name}</div>
          <div style="color: var(--fbc-text-dim); font-size: 10px;">{obj.description}</div>
        </div>
      </div>
    </div>

    <%!-- === CONTAINMENT RECORDS / CREATURE ROSTER (top-right) === --%>
    <div
      :if={@show_creatures}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 260px; max-width: 320px; max-height: 60vh; overflow-y: auto; border: 1px solid var(--fbc-border);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
          Containment Records
        </span>
        <span style="font-size: 10px; color: var(--fbc-text-dim);">
          {length(@creature_roster)} contained
        </span>
      </div>
      <div :if={@creature_roster == []} style="color: var(--fbc-text-dim); font-size: 11px;">
        No entities contained. Deploy a Containment Array near altered entities.
      </div>
      <div
        :for={creature <- @creature_roster}
        style="margin-bottom: 8px; padding: 8px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);"
      >
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="color: var(--fbc-highlight); font-size: 12px;">
            {Creatures.display_name(creature.type)}
          </span>
          <span style="font-size: 10px; color: var(--fbc-text-dim);">
            {creature_boost_label(creature.type)}
          </span>
        </div>
        <div
          :if={creature.assigned_to}
          style="color: var(--fbc-text-dim); font-size: 10px; margin-top: 2px;"
        >
          Assigned: {format_building_key(creature.assigned_to)}
          <button
            phx-click="unassign_creature"
            phx-value-creature_id={creature.id}
            style="margin-left: 6px; padding: 2px 6px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.15); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
          >
            Recall
          </button>
        </div>
        <div
          :if={creature.assigned_to == nil}
          style="color: var(--fbc-text-dim); font-size: 10px; margin-top: 2px;"
        >
          Unassigned — select a structure to deploy
        </div>
        <button
          :if={(creature.assigned_to == nil and @tile_info) && @tile_info.building}
          phx-click="assign_creature"
          phx-value-creature_id={creature.id}
          phx-value-face={@tile_info.face}
          phx-value-row={@tile_info.row}
          phx-value-col={@tile_info.col}
          style="margin-top: 4px; padding: 3px 8px; border: 1px solid var(--fbc-success); background: rgba(102,136,68,0.12); color: var(--fbc-success); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
        >
          Deploy to selected structure
        </button>
      </div>
    </div>

    <%!-- === TRADE EXCHANGE PANEL (top-right) === --%>
    <div
      :if={@show_trading}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 280px; max-width: 360px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-border);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
          Exchange Requisitions
        </span>
        <span style="font-size: 10px; color: var(--fbc-text-dim);">
          {length(@open_trades)} open
        </span>
      </div>
      <%!-- My active trades --%>
      <div
        :if={@my_trades != []}
        style="margin-bottom: 12px;"
      >
        <div style="font-size: 10px; color: var(--fbc-accent); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 6px;">
          Your Requisitions
        </div>
        <div
          :for={trade <- @my_trades}
          style={"margin-bottom: 8px; padding: 8px; border: 1px solid #{trade_status_color(trade.status)}; background: rgba(255,255,255,0.02);"}
        >
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <span style={"color: #{trade_status_color(trade.status)}; font-size: 10px; text-transform: uppercase;"}>
              {trade.status}
            </span>
            <button
              :if={trade.status in ["open", "accepted"] and trade.offerer_id == @player_id}
              phx-click="cancel_trade"
              phx-value-trade_id={trade.id}
              style="padding: 2px 6px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.15); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
            >
              Cancel
            </button>
          </div>
          <div style="margin-top: 4px; font-size: 11px;">
            <span style="color: var(--fbc-text-dim);">Offering:</span>
            <span
              :for={{item, count} <- trade.offered_items}
              style="color: var(--fbc-highlight); margin-left: 4px;"
            >
              {Lore.display_name_str(item)} x{count}
            </span>
          </div>
          <div style="font-size: 11px;">
            <span style="color: var(--fbc-text-dim);">Requesting:</span>
            <span
              :for={{item, count} <- trade.requested_items}
              style="color: var(--fbc-info); margin-left: 4px;"
            >
              {Lore.display_name_str(item)} x{count}
            </span>
          </div>
          <%!-- Link to trade terminal button --%>
          <button
            :if={
              (trade.status == "accepted" and @tile_info) && @tile_info.building &&
                @tile_info.building.type == :trade_terminal
            }
            phx-click="link_trade"
            phx-value-trade_id={trade.id}
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style="margin-top: 4px; padding: 3px 8px; border: 1px solid var(--fbc-success); background: rgba(102,136,68,0.12); color: var(--fbc-success); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
          >
            Link to selected terminal
          </button>
        </div>
      </div>
      <%!-- Open trades from other players --%>
      <div style="font-size: 10px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 6px;">
        Open Requisitions
      </div>
      <div :if={@open_trades == []} style="color: var(--fbc-text-dim); font-size: 11px;">
        No open requisitions available.
      </div>
      <div
        :for={trade <- @open_trades}
        :if={trade.offerer_id != @player_id}
        style="margin-bottom: 8px; padding: 8px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);"
      >
        <div style="font-size: 11px;">
          <span style="color: var(--fbc-text-dim);">Offering:</span>
          <span
            :for={{item, count} <- trade.offered_items}
            style="color: var(--fbc-highlight); margin-left: 4px;"
          >
            {Lore.display_name_str(item)} x{count}
          </span>
        </div>
        <div style="font-size: 11px;">
          <span style="color: var(--fbc-text-dim);">Wants:</span>
          <span
            :for={{item, count} <- trade.requested_items}
            style="color: var(--fbc-info); margin-left: 4px;"
          >
            {Lore.display_name_str(item)} x{count}
          </span>
        </div>
        <button
          phx-click="accept_trade"
          phx-value-trade_id={trade.id}
          style="margin-top: 4px; padding: 3px 8px; border: 1px solid var(--fbc-success); background: rgba(102,136,68,0.12); color: var(--fbc-success); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
        >
          Accept Requisition
        </button>
      </div>
    </div>

    <%!-- === RECIPE BROWSER PANEL (top-right) === --%>
    <div
      :if={@show_recipes}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 300px; max-width: 380px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-border);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
          Bureau Protocols
        </span>
        <span style="font-size: 10px; color: var(--fbc-text-dim);">
          {length(@recipes)} protocols
        </span>
      </div>
      <form phx-change="recipe_search" style="margin-bottom: 10px;">
        <input
          type="text"
          name="query"
          value={@recipe_search}
          placeholder="Search protocols..."
          phx-debounce="200"
          style="width: 100%; padding: 6px 10px; background: rgba(255,255,255,0.04); border: 1px solid var(--fbc-border); color: var(--fbc-text); font-family: 'Courier New', monospace; font-size: 11px; box-sizing: border-box;"
        />
      </form>
      <div
        :for={recipe <- @recipes}
        style="margin-bottom: 8px; padding: 8px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);"
      >
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="color: var(--fbc-highlight); font-size: 11px;">{recipe.building_name}</span>
        </div>
        <div style="margin-top: 4px; font-size: 11px;">
          <span style="color: var(--fbc-text-dim);">Input:</span>
          <span
            :for={input <- recipe.inputs}
            style="color: var(--fbc-info); margin-left: 4px;"
          >
            {input.name}
          </span>
        </div>
        <div style="font-size: 11px;">
          <span style="color: var(--fbc-text-dim);">Output:</span>
          <span style="color: var(--fbc-success); margin-left: 4px;">
            {recipe.output.name}
          </span>
        </div>
      </div>
    </div>

    <%!-- === PRODUCTION STATISTICS PANEL (top-right) === --%>
    <div
      :if={@show_stats}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 300px; max-width: 380px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-border);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
          Production Report
        </span>
        <span style="font-size: 10px; color: var(--fbc-text-dim);">
          {length(@stats_summary)} active
        </span>
      </div>
      <div :if={@stats_summary == []} style="color: var(--fbc-text-dim); font-size: 11px;">
        No production data recorded yet.
      </div>
      <div
        :for={stat <- Enum.take(@stats_summary, 20)}
        style="margin-bottom: 6px; padding: 6px 8px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);"
      >
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="color: var(--fbc-highlight); font-size: 11px;">
            {Lore.display_name(stat.type)}
          </span>
          <span style="color: var(--fbc-text-dim); font-size: 9px;">
            {format_building_key(stat.key)}
          </span>
        </div>
        <div :if={stat.produced != %{}} style="font-size: 10px; margin-top: 2px;">
          <span style="color: var(--fbc-text-dim);">Produced:</span>
          <span
            :for={{item, count} <- stat.produced}
            style="color: var(--fbc-success); margin-left: 4px;"
          >
            {Lore.display_name(item)} x{count}
          </span>
        </div>
        <div :if={stat.consumed != %{}} style="font-size: 10px;">
          <span style="color: var(--fbc-text-dim);">Consumed:</span>
          <span
            :for={{item, count} <- stat.consumed}
            style="color: var(--fbc-info); margin-left: 4px;"
          >
            {Lore.display_name(item)} x{count}
          </span>
        </div>
        <div :if={stat.throughput != %{}} style="font-size: 10px;">
          <span style="color: var(--fbc-text-dim);">Throughput:</span>
          <span
            :for={{item, count} <- stat.throughput}
            style="color: var(--fbc-highlight); margin-left: 4px;"
          >
            {Lore.display_name(item)} x{count}
          </span>
        </div>
      </div>
    </div>

    <%!-- === BOARD MESSAGE (top-center overlay) === --%>
    <div
      :if={@board_message}
      id="board-message"
      style="position: fixed; top: 60px; left: 50%; transform: translateX(-50%); background: rgba(10,8,6,0.92); color: var(--fbc-cream); padding: 16px 28px; border: 1px solid var(--fbc-gold); font-family: 'Courier New', monospace; font-size: 14px; line-height: 1.8; pointer-events: auto; max-width: 500px; text-align: center; letter-spacing: 0.08em; text-transform: uppercase; animation: fadeIn 1s ease-in;"
    >
      <div style="font-size: 9px; color: var(--fbc-gold); letter-spacing: 0.2em; margin-bottom: 8px;">
        THE BOARD
      </div>
      <div style="color: var(--fbc-cream);">{@board_message}</div>
      <button
        phx-click="dismiss_board_message"
        style="margin-top: 10px; padding: 4px 16px; border: 1px solid var(--fbc-gold); background: rgba(204,170,68,0.1); color: var(--fbc-gold); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em;"
      >
        Acknowledged
      </button>
    </div>

    <%!-- === WORLD EVENT NOTIFICATION (top-center) === --%>
    <div
      :if={@active_event}
      style="position: fixed; top: 16px; left: 50%; transform: translateX(-50%); background: rgba(10,8,6,0.88); color: var(--fbc-accent); padding: 8px 20px; border: 1px solid var(--fbc-accent); font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.12em; pointer-events: none; animation: pulse 2s ease-in-out infinite;"
    >
      {world_event_label(@active_event)}
    </div>

    <%!-- === SHIFT CYCLE INDICATOR (bottom-left) === --%>
    <div style="position: fixed; bottom: 60px; left: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 6px 12px; border: 1px solid var(--fbc-border); font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; pointer-events: none;">
      <span style={"color: #{shift_phase_color(@shift_phase)};"}>
        {shift_phase_label(@shift_phase)}
      </span>
    </div>

    <%!-- === BOARD CONTACT QUEST PANEL (top-right) === --%>
    <div
      :if={@show_board_contact}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 300px; max-width: 380px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-gold);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-gold); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-gold); text-transform: uppercase; letter-spacing: 0.15em;">
          Board Contact
        </span>
        <span style={"font-size: 10px; color: #{if @board_contact.completed, do: "var(--fbc-success)", else: "var(--fbc-accent)"}; text-transform: uppercase;"}>
          {if @board_contact.completed, do: "ESTABLISHED", else: "#{@board_contact.progress_pct}%"}
        </span>
      </div>
      <div :if={not @board_contact.active} style="color: var(--fbc-text-dim); font-size: 11px; margin-bottom: 8px;">
        Quest not yet activated. Requires Clearance L3.
        <button
          :if={@clearance_level >= 3}
          phx-click="activate_board_contact"
          style="display: block; margin-top: 8px; padding: 6px 14px; border: 1px solid var(--fbc-gold); background: rgba(204,170,68,0.1); color: var(--fbc-gold); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em;"
        >
          Initiate Contact Protocol
        </button>
      </div>
      <div :if={@board_contact.active}>
        <div style="background: var(--fbc-border); height: 4px; margin-bottom: 10px;">
          <div style={"background: var(--fbc-gold); height: 4px; width: #{@board_contact.progress_pct}%;"}>
          </div>
        </div>
        <div
          :for={req <- @board_contact.requirements}
          style={"margin-bottom: 6px; padding: 6px 8px; border: 1px solid #{if req.complete, do: "var(--fbc-success)", else: "var(--fbc-border)"}; background: #{if req.complete, do: "rgba(102,136,68,0.08)", else: "rgba(255,255,255,0.02)"};"}
        >
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <span style={"color: #{if req.complete, do: "var(--fbc-success)", else: "var(--fbc-highlight)"}; font-size: 11px;"}>
              {Lore.display_name(req.item)}
            </span>
            <span style="color: var(--fbc-text-dim); font-size: 10px;">
              {req.submitted}/{req.required}
            </span>
          </div>
          <div style="background: var(--fbc-border); height: 3px; margin-top: 2px;">
            <div style={"background: #{if req.complete, do: "var(--fbc-success)", else: "var(--fbc-gold)"}; height: 3px; width: #{min(100, trunc(req.submitted / max(req.required, 1) * 100))}%;"}>
            </div>
          </div>
        </div>
        <div
          :if={map_size(@board_contact.contributors) > 0}
          style="margin-top: 8px; border-top: 1px solid var(--fbc-border); padding-top: 6px; font-size: 10px; color: var(--fbc-text-dim);"
        >
          {map_size(@board_contact.contributors)} contributors &middot; {@board_contact.total_submitted}/{@board_contact.total_required} total
        </div>
      </div>
    </div>

    <%!-- === BOTTOM TOOLBAR === --%>
    <div style="position: fixed; bottom: 0; left: 0; right: 0; display: flex; justify-content: center; gap: 4px; padding: 12px; background: var(--fbc-panel); border-top: 1px solid var(--fbc-border); pointer-events: auto;">
      <button
        phx-click="toggle_research"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_research, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @show_research, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_research, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
        "}
        title="Case Files (F key)"
      >
        Case Files
      </button>
      <button
        phx-click="toggle_creatures"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_creatures, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @show_creatures, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_creatures, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          margin-right: 8px;
        "}
        title="Containment Records (C key)"
      >
        Entities
      </button>
      <button
        phx-click="toggle_trading"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_trading, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @show_trading, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_trading, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          margin-right: 8px;
        "}
        title="Exchange Requisitions (T key)"
      >
        Trades
      </button>
      <button
        phx-click="toggle_recipes"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_recipes, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @show_recipes, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_recipes, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
        "}
        title="Bureau Protocols (B key)"
      >
        Protocols
      </button>
      <button
        phx-click="toggle_stats"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_stats, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @show_stats, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_stats, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          margin-right: 8px;
        "}
        title="Production Report (P key)"
      >
        Report
      </button>
      <button
        phx-click="toggle_board_contact"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @show_board_contact, do: "var(--fbc-gold)", else: "var(--fbc-border)"};
          background: #{if @show_board_contact, do: "rgba(204,170,68,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @show_board_contact, do: "var(--fbc-gold)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
        "}
        title="Board Contact (G key)"
      >
        Contact
      </button>
      <button
        phx-click="blueprint_capture"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @blueprint_mode == :capture, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @blueprint_mode == :capture, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @blueprint_mode == :capture, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          margin-right: 8px;
        "}
        title="Capture blueprint (select area)"
      >
        Capture
      </button>
      <button
        :if={@blueprint_count > 0}
        phx-click="blueprint_stamp"
        style={"
          padding: 8px 12px;
          border: 1px solid #{if @blueprint_mode == :stamp, do: "var(--fbc-highlight)", else: "var(--fbc-border)"};
          background: #{if @blueprint_mode == :stamp, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @blueprint_mode == :stamp, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
        "}
        title="Stamp last blueprint"
      >
        Stamp
      </button>
      <button
        :for={type <- @building_types}
        phx-click="select_building"
        phx-value-type={type}
        style={"
          padding: 8px 14px;
          border: 1px solid #{if @selected_building_type == type, do: "var(--fbc-accent)", else: "var(--fbc-border)"};
          background: #{if @selected_building_type == type, do: "rgba(204,51,51,0.15)", else: "rgba(255,255,255,0.04)"};
          color: #{if @selected_building_type == type, do: "var(--fbc-accent)", else: "var(--fbc-text)"};
          cursor: pointer;
          font-family: 'Courier New', monospace;
          font-size: 12px;
          font-weight: #{if @selected_building_type == type, do: "bold", else: "normal"};
          text-transform: uppercase;
          letter-spacing: 0.05em;
        "}
      >
        {Lore.display_name(type)}
      </button>
      <div
        :if={@selected_building_type}
        style="display: flex; align-items: center; gap: 4px; margin-left: 8px; padding-left: 8px; border-left: 1px solid var(--fbc-border);"
      >
        <button
          phx-click="rotate_building"
          style="padding: 8px 12px; border: 1px solid var(--fbc-border-light); background: rgba(255,255,255,0.04); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase;"
          title="Rotate (R key)"
        >
          {direction_label(@placement_orientation)}
        </button>
        <button
          phx-click="toggle_line_mode"
          style={"padding: 8px 12px; border: 1px solid #{if @line_mode, do: "var(--fbc-highlight)", else: "var(--fbc-border-light)"}; background: #{if @line_mode, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @line_mode, do: "var(--fbc-highlight)", else: "var(--fbc-info)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase; font-weight: #{if @line_mode, do: "bold", else: "normal"};"}
          title="Line draw mode (L key)"
        >
          Line
        </button>
        <button
          phx-click="select_building"
          phx-value-type="none"
          style="padding: 8px 14px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.04); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase;"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("select_building", %{"type" => "none"}, socket) do
    socket =
      socket
      |> assign(:selected_building_type, nil)
      |> assign(:line_mode, false)
      |> assign(:blueprint_mode, nil)
      |> push_event("placement_mode", %{type: nil, orientation: nil})
      |> push_event("line_mode", %{enabled: false})
      |> push_event("blueprint_mode", %{mode: nil})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_building", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if Buildings.valid_type?(type) do
      orientation = socket.assigns.placement_orientation

      socket =
        socket
        |> assign(:selected_building_type, type)
        |> assign(:blueprint_mode, nil)
        |> push_event("placement_mode", %{type: type_str, orientation: orientation})
        |> push_event("blueprint_mode", %{mode: nil})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("rotate_building", _params, socket) do
    new_orientation = rem(socket.assigns.placement_orientation + 3, 4)

    socket =
      socket
      |> assign(:placement_orientation, new_orientation)
      |> push_event("placement_mode", %{
        type: Atom.to_string(socket.assigns.selected_building_type),
        orientation: new_orientation
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_line_mode", _params, socket) do
    if socket.assigns.selected_building_type do
      new_line_mode = !socket.assigns.line_mode

      socket =
        socket
        |> assign(:line_mode, new_line_mode)
        |> push_event("line_mode", %{enabled: new_line_mode})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("place_line", %{"buildings" => buildings_list}, socket) do
    case socket.assigns.selected_building_type do
      nil ->
        {:noreply, socket}

      building_type ->
        owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

        placements =
          Enum.map(buildings_list, fn %{
                                        "face" => face,
                                        "row" => row,
                                        "col" => col,
                                        "orientation" => orientation
                                      } ->
            {{face, row, col}, building_type, orientation, owner}
          end)

        results = WorldServer.place_buildings(placements)

        socket =
          Enum.reduce(results, socket, fn
            {{face, row, col}, :ok}, sock ->
              building = WorldStore.get_building({face, row, col})

              push_event(sock, "building_placed", %{
                face: face,
                row: row,
                col: col,
                type: Atom.to_string(building.type),
                orientation: building.orientation
              })

            {{face, row, col}, {:error, reason}}, sock ->
              push_event(sock, "place_error", %{
                face: face,
                row: row,
                col: col,
                reason: Atom.to_string(reason)
              })
          end)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("tile_click", %{"face" => face, "row" => row, "col" => col}, socket) do
    key = {face, row, col}
    tile = %{face: face, row: row, col: col}
    Logger.debug("Tile clicked: face=#{face} row=#{row} col=#{col}")

    case socket.assigns.selected_building_type do
      nil ->
        tile_info = build_tile_info(key)

        socket =
          socket
          |> assign(:selected_tile, tile)
          |> assign(:tile_info, tile_info)

        {:noreply, socket}

      building_type ->
        orientation = socket.assigns.placement_orientation

        owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

        case WorldServer.place_building(key, building_type, orientation, owner) do
          :ok ->
            building = WorldStore.get_building(key)
            tile_info = build_tile_info(key)

            socket =
              socket
              |> assign(:selected_tile, tile)
              |> assign(:tile_info, tile_info)
              |> push_event("building_placed", %{
                face: face,
                row: row,
                col: col,
                type: Atom.to_string(building.type),
                orientation: building.orientation
              })

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> push_event("place_error", %{
                face: face,
                row: row,
                col: col,
                reason: Atom.to_string(reason)
              })

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("remove_building", %{"face" => face, "row" => row, "col" => col}, socket) do
    face = to_int(face)
    row = to_int(row)
    col = to_int(col)
    key = {face, row, col}

    case WorldServer.remove_building(key, socket.assigns.player_id) do
      :ok ->
        tile_info = build_tile_info(key)

        socket =
          socket
          |> assign(:tile_info, tile_info)
          |> push_event("building_removed", %{face: face, row: row, col: col})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_research", _params, socket) do
    opening = !socket.assigns.show_research

    socket =
      socket
      |> assign(:show_research, opening)
      |> then(fn s -> if opening, do: assign(s, :show_creatures, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_trading, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_recipes, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_stats, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_board_contact, false), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_creatures", _params, socket) do
    opening = !socket.assigns.show_creatures
    roster = Creatures.get_player_roster(socket.assigns.player_id)

    socket =
      socket
      |> assign(:show_creatures, opening)
      |> assign(:creature_roster, roster)
      |> then(fn s -> if opening, do: assign(s, :show_research, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_trading, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_recipes, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_stats, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_board_contact, false), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "assign_creature",
        %{"creature_id" => creature_id, "face" => face, "row" => row, "col" => col},
        socket
      ) do
    building_key = {to_int(face), to_int(row), to_int(col)}

    case Creatures.assign_creature(socket.assigns.player_id, creature_id, building_key) do
      :ok ->
        roster = Creatures.get_player_roster(socket.assigns.player_id)
        {:noreply, assign(socket, :creature_roster, roster)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("unassign_creature", %{"creature_id" => creature_id}, socket) do
    case Creatures.unassign_creature(socket.assigns.player_id, creature_id) do
      :ok ->
        roster = Creatures.get_player_roster(socket.assigns.player_id)
        {:noreply, assign(socket, :creature_roster, roster)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_trading", _params, socket) do
    opening = !socket.assigns.show_trading
    world_id = socket.assigns.world_id
    player_id = socket.assigns.player_id

    socket =
      if opening and world_id do
        open_trades = Trading.open_trades(world_id)
        my_trades = Trading.player_trades(world_id, player_id)

        socket
        |> assign(:show_trading, true)
        |> assign(:open_trades, open_trades)
        |> assign(:my_trades, my_trades)
        |> assign(:show_research, false)
        |> assign(:show_creatures, false)
      else
        assign(socket, :show_trading, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_trade", %{"offered" => offered, "requested" => requested}, socket) do
    world_id = socket.assigns.world_id
    player_id = socket.assigns.player_id

    if world_id do
      case Trading.create_trade(world_id, player_id, offered, requested) do
        {:ok, _trade} ->
          open_trades = Trading.open_trades(world_id)
          my_trades = Trading.player_trades(world_id, player_id)

          socket =
            socket
            |> assign(:open_trades, open_trades)
            |> assign(:my_trades, my_trades)

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("accept_trade", %{"trade_id" => trade_id_str}, socket) do
    trade_id = String.to_integer(trade_id_str)
    player_id = socket.assigns.player_id
    world_id = socket.assigns.world_id

    case Trading.accept_trade(trade_id, player_id) do
      {:ok, _trade} ->
        open_trades = Trading.open_trades(world_id)
        my_trades = Trading.player_trades(world_id, player_id)

        socket =
          socket
          |> assign(:open_trades, open_trades)
          |> assign(:my_trades, my_trades)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_trade", %{"trade_id" => trade_id_str}, socket) do
    trade_id = String.to_integer(trade_id_str)
    player_id = socket.assigns.player_id
    world_id = socket.assigns.world_id

    case Trading.cancel_trade(trade_id, player_id) do
      {:ok, _trade} ->
        open_trades = Trading.open_trades(world_id)
        my_trades = Trading.player_trades(world_id, player_id)

        socket =
          socket
          |> assign(:open_trades, open_trades)
          |> assign(:my_trades, my_trades)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "link_trade",
        %{"trade_id" => trade_id_str, "face" => face, "row" => row, "col" => col},
        socket
      ) do
    trade_id = String.to_integer(trade_id_str)
    key = {to_int(face), to_int(row), to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :trade_terminal &&
         building.owner_id == socket.assigns.player_id do
      new_state = %{building.state | trade_id: trade_id}
      WorldStore.put_building(key, %{building | state: new_state})
      tile_info = build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "f"}, socket) do
    opening = !socket.assigns.show_research

    socket =
      socket
      |> assign(:show_research, opening)
      |> then(fn s -> if opening, do: assign(s, :show_creatures, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_trading, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_recipes, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_stats, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_board_contact, false), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "c"}, socket) do
    opening = !socket.assigns.show_creatures
    roster = Creatures.get_player_roster(socket.assigns.player_id)

    socket =
      socket
      |> assign(:show_creatures, opening)
      |> assign(:creature_roster, roster)
      |> then(fn s -> if opening, do: assign(s, :show_research, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_trading, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_recipes, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_stats, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_board_contact, false), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => "t"}, socket) do
    handle_event("toggle_trading", %{}, socket)
  end

  @impl true
  def handle_event("keydown", %{"key" => "r"}, socket) do
    if socket.assigns.selected_building_type do
      new_orientation = rem(socket.assigns.placement_orientation + 3, 4)

      socket =
        socket
        |> assign(:placement_orientation, new_orientation)
        |> push_event("placement_mode", %{
          type: Atom.to_string(socket.assigns.selected_building_type),
          orientation: new_orientation
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "l"}, socket) do
    if socket.assigns.selected_building_type do
      new_line_mode = !socket.assigns.line_mode

      socket =
        socket
        |> assign(:line_mode, new_line_mode)
        |> push_event("line_mode", %{enabled: new_line_mode})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "b"}, socket) do
    handle_event("toggle_recipes", %{}, socket)
  end

  @impl true
  def handle_event("keydown", %{"key" => "p"}, socket) do
    handle_event("toggle_stats", %{}, socket)
  end

  @impl true
  def handle_event("keydown", %{"key" => "g"}, socket) do
    handle_event("toggle_board_contact", %{}, socket)
  end

  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_recipes", _params, socket) do
    opening = !socket.assigns.show_recipes

    socket =
      socket
      |> assign(:show_recipes, opening)
      |> then(fn s -> if opening, do: assign(s, :show_research, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_creatures, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_trading, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_stats, false), else: s end)
      |> then(fn s -> if opening, do: assign(s, :show_board_contact, false), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("recipe_search", %{"query" => query}, socket) do
    recipes =
      if query == "" do
        RecipeBrowser.all_recipes()
      else
        RecipeBrowser.search(query)
      end

    socket =
      socket
      |> assign(:recipe_search, query)
      |> assign(:recipes, recipes)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_stats", _params, socket) do
    opening = !socket.assigns.show_stats

    socket =
      if opening do
        summary = Statistics.player_summary(socket.assigns.player_id)

        socket
        |> assign(:show_stats, true)
        |> assign(:stats_summary, summary)
        |> assign(:show_research, false)
        |> assign(:show_creatures, false)
        |> assign(:show_trading, false)
        |> assign(:show_recipes, false)
        |> assign(:show_board_contact, false)
      else
        assign(socket, :show_stats, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_board_contact", _params, socket) do
    opening = !socket.assigns.show_board_contact

    socket =
      if opening do
        summary = BoardContact.progress_summary()

        socket
        |> assign(:show_board_contact, true)
        |> assign(:board_contact, summary)
        |> assign(:show_research, false)
        |> assign(:show_creatures, false)
        |> assign(:show_trading, false)
        |> assign(:show_recipes, false)
        |> assign(:show_stats, false)
      else
        assign(socket, :show_board_contact, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_board_message", _params, socket) do
    {:noreply, assign(socket, :board_message, nil)}
  end

  @impl true
  def handle_event("activate_board_contact", _params, socket) do
    if socket.assigns.clearance_level >= 3 do
      BoardContact.activate()
      summary = BoardContact.progress_summary()

      # Check for Board milestone
      messages = TheBoard.check_milestones(socket.assigns.player_id, %{board_contact_begin: true})

      socket =
        socket
        |> assign(:board_contact, summary)
        |> then(fn s ->
          case messages do
            [{_milestone, msg} | _] -> assign(s, :board_message, msg)
            _ -> s
          end
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Blueprint events ---

  @impl true
  def handle_event("blueprint_capture", _params, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :capture)
      |> assign(:selected_building_type, nil)
      |> push_event("blueprint_mode", %{mode: "capture"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("blueprint_stamp", _params, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :stamp)
      |> assign(:selected_building_type, nil)
      |> push_event("blueprint_mode", %{mode: "stamp"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("blueprint_captured", %{"name" => _name, "count" => _count}, socket) do
    socket =
      socket
      |> assign(:blueprint_mode, :stamp)
      |> assign(:blueprint_count, socket.assigns.blueprint_count + 1)

    {:noreply, socket}
  end

  @impl true
  def handle_event("blueprint_cancelled", _params, socket) do
    {:noreply, assign(socket, :blueprint_mode, nil)}
  end

  @impl true
  def handle_event("place_blueprint", %{"buildings" => buildings_list}, socket) do
    owner = %{id: socket.assigns.player_id, name: socket.assigns.player_name}

    placements =
      Enum.map(buildings_list, fn %{
                                    "face" => face,
                                    "row" => row,
                                    "col" => col,
                                    "orientation" => orientation,
                                    "type" => type_str
                                  } ->
        {{face, row, col}, String.to_existing_atom(type_str), orientation, owner}
      end)

    results = WorldServer.place_buildings(placements)

    socket =
      Enum.reduce(results, socket, fn
        {{face, row, col}, :ok}, sock ->
          building = WorldStore.get_building({face, row, col})

          push_event(sock, "building_placed", %{
            face: face,
            row: row,
            col: col,
            type: Atom.to_string(building.type),
            orientation: building.orientation
          })

        {{_face, _row, _col}, {:error, _reason}}, sock ->
          sock
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "link_conduit",
        %{
          "face" => face,
          "row" => row,
          "col" => col,
          "target_face" => tf,
          "target_row" => tr,
          "target_col" => tc
        },
        socket
      ) do
    key_a = {to_int(face), to_int(row), to_int(col)}
    key_b = {to_int(tf), to_int(tr), to_int(tc)}

    building_a = WorldStore.get_building(key_a)
    building_b = WorldStore.get_building(key_b)

    if building_a && building_b &&
         building_a.type == :underground_conduit &&
         building_b.type == :underground_conduit &&
         building_a.owner_id == socket.assigns.player_id &&
         building_b.owner_id == socket.assigns.player_id do
      new_state_a = %{building_a.state | linked_to: key_b}
      new_state_b = %{building_b.state | linked_to: key_a}
      WorldStore.put_building(key_a, %{building_a | state: new_state_a})
      WorldStore.put_building(key_b, %{building_b | state: new_state_b})

      tile_info = build_tile_info(key_a)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("camera_update", %{"x" => x, "y" => y, "z" => z}, socket) do
    camera_pos = {x, y, z}
    visible = Coordinate.visible_faces(camera_pos) |> MapSet.new()

    # Dynamic face subscriptions: subscribe to new, unsubscribe from old
    old_faces = socket.assigns.subscribed_faces
    new_faces = visible
    to_subscribe = MapSet.difference(new_faces, old_faces)
    to_unsubscribe = MapSet.difference(old_faces, new_faces)

    for face_id <- MapSet.to_list(to_subscribe) do
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:face:#{face_id}")
    end

    for face_id <- MapSet.to_list(to_unsubscribe) do
      Phoenix.PubSub.unsubscribe(Spheric.PubSub, "world:face:#{face_id}")
    end

    # Update presence with new camera position
    Presence.update(self(), @presence_topic, socket.assigns.player_id, fn meta ->
      Map.put(meta, :camera, %{x: x, y: y, z: z})
    end)

    socket =
      socket
      |> assign(:camera_pos, camera_pos)
      |> assign(:visible_faces, visible)
      |> assign(:subscribed_faces, new_faces)

    {:noreply, socket}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:building_placed, {face, row, col}, building}, socket) do
    socket =
      push_event(socket, "building_placed", %{
        face: face,
        row: row,
        col: col,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:building_removed, {face, row, col}}, socket) do
    socket = push_event(socket, "building_removed", %{face: face, row: row, col: col})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:tick_update, tick, face_id, items}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      serialized_items =
        Enum.map(items, fn item ->
          %{
            row: item.row,
            col: item.col,
            item: Atom.to_string(item.item),
            from_face: item.from_face,
            from_row: item.from_row,
            from_col: item.from_col
          }
        end)

      socket =
        push_event(socket, "tick_items", %{
          tick: tick,
          face: face_id,
          items: serialized_items
        })

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Research Handlers ---

  @impl true
  def handle_info({:case_file_completed, _case_file_id}, socket) do
    refresh_research(socket)
  end

  @impl true
  def handle_info({:research_progress, _item}, socket) do
    refresh_research(socket)
  end

  @impl true
  def handle_info({:object_of_power_granted, _object}, socket) do
    objects = ObjectsOfPower.player_objects(socket.assigns.player_id)
    {:noreply, assign(socket, :objects_of_power, objects)}
  end

  # --- Creature Handlers ---

  @impl true
  def handle_info({:creature_spawned, id, creature}, socket) do
    socket =
      push_event(socket, "creature_spawned", %{
        id: id,
        creature: %{
          type: Atom.to_string(creature.type),
          face: creature.face,
          row: creature.row,
          col: creature.col
        }
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:creature_moved, id, creature}, socket) do
    socket =
      push_event(socket, "creature_moved", %{
        id: id,
        creature: %{
          type: Atom.to_string(creature.type),
          face: creature.face,
          row: creature.row,
          col: creature.col
        }
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:creature_captured, creature_id, _creature, _trap_key}, socket) do
    socket = push_event(socket, "creature_captured", %{id: creature_id})

    # Refresh roster for the current player
    roster = Creatures.get_player_roster(socket.assigns.player_id)
    {:noreply, assign(socket, :creature_roster, roster)}
  end

  @impl true
  def handle_info({:creature_sync, face_id, creatures}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      serialized =
        Enum.map(creatures, fn c ->
          %{id: c.id, type: Atom.to_string(c.type), face: c.face, row: c.row, col: c.col}
        end)

      socket = push_event(socket, "creature_sync", %{face: face_id, creatures: serialized})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Hiss Corruption Handlers ---

  @impl true
  def handle_info({:corruption_update, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_update", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:corruption_cleared, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_cleared", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:corruption_sync, face_id, tiles}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "corruption_sync", %{face: face_id, tiles: tiles})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:hiss_spawned, id, entity}, socket) do
    socket =
      push_event(socket, "hiss_spawned", %{
        id: id,
        entity: %{face: entity.face, row: entity.row, col: entity.col, health: entity.health}
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:hiss_moved, id, entity}, socket) do
    socket =
      push_event(socket, "hiss_moved", %{
        id: id,
        entity: %{face: entity.face, row: entity.row, col: entity.col, health: entity.health}
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:hiss_killed, id, _killer}, socket) do
    socket = push_event(socket, "hiss_killed", %{id: id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:hiss_sync, face_id, entities}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket = push_event(socket, "hiss_sync", %{face: face_id, entities: entities})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:building_damage, {face, row, col}, action}, socket) do
    socket =
      push_event(socket, "building_damaged", %{
        face: face,
        row: row,
        col: col,
        action: Atom.to_string(action)
      })

    # If the building was destroyed, update tile info if selected
    socket =
      if action == :destroyed and socket.assigns.selected_tile do
        sel = socket.assigns.selected_tile

        if sel.face == face and sel.row == row and sel.col == col do
          assign(socket, :tile_info, build_tile_info({face, row, col}))
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Territory Handlers ---

  @impl true
  def handle_info({:territory_update, face_id, territories}, socket) do
    if MapSet.member?(socket.assigns.visible_faces, face_id) do
      socket =
        push_event(socket, "territory_update", %{face: face_id, territories: territories})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Phase 8: World Events, Shift Cycle, Creature Evolution ---

  @impl true
  def handle_info({:world_event_started, event_type, event_info}, socket) do
    # Check for Board milestone
    messages =
      TheBoard.check_milestones(socket.assigns.player_id, %{first_world_event: true})

    socket =
      socket
      |> assign(:active_event, event_type)
      |> push_event("world_event_started", %{
        event: Atom.to_string(event_type),
        name: event_info.name,
        color: event_info.color
      })
      |> then(fn s ->
        case messages do
          [{_milestone, msg} | _] -> assign(s, :board_message, msg)
          _ -> s
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:world_event_ended, event_type}, socket) do
    socket =
      socket
      |> assign(:active_event, nil)
      |> push_event("world_event_ended", %{event: Atom.to_string(event_type)})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:shift_cycle_changed, phase, lighting, _modifiers}, socket) do
    socket =
      socket
      |> assign(:shift_phase, phase)
      |> push_event("shift_cycle_changed", %{
        phase: Atom.to_string(phase),
        ambient: lighting.ambient,
        directional: lighting.directional,
        intensity: lighting.intensity,
        bg: lighting.bg
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:creature_evolved, player_id, _creature_id, _creature}, socket) do
    if player_id == socket.assigns.player_id do
      # Check for Board milestone
      messages =
        TheBoard.check_milestones(socket.assigns.player_id, %{creature_evolved: true})

      roster = Creatures.get_player_roster(socket.assigns.player_id)

      socket =
        socket
        |> assign(:creature_roster, roster)
        |> then(fn s ->
          case messages do
            [{_milestone, msg} | _] -> assign(s, :board_message, msg)
            _ -> s
          end
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # --- Terrain Streaming ---

  @impl true
  def handle_info(:send_terrain, socket) do
    subdivisions = Application.get_env(:spheric, :subdivisions, 64)

    socket =
      Enum.reduce(0..29, socket, fn face_id, sock ->
        terrain = build_face_terrain(face_id, subdivisions)

        altered =
          AlteredItems.get_face_items(face_id)
          |> Enum.map(fn {{_f, row, col}, type_id} ->
            info = AlteredItems.get_type(type_id)
            %{row: row, col: col, type: Atom.to_string(type_id), color: info.color}
          end)

        corruption = Hiss.corrupted_on_face(face_id)

        hiss_entities =
          Hiss.hiss_entities_on_face(face_id)
          |> Enum.map(fn {id, e} ->
            %{id: id, face: e.face, row: e.row, col: e.col, health: e.health}
          end)

        territories = Territory.territories_on_face(face_id)

        sock
        |> push_event("terrain_face", %{face: face_id, terrain: terrain})
        |> push_event("altered_items", %{face: face_id, items: altered})
        |> push_event("corruption_sync", %{face: face_id, tiles: corruption})
        |> push_event("hiss_sync", %{face: face_id, entities: hiss_entities})
        |> push_event("territory_sync", %{face: face_id, territories: territories})
      end)

    {:noreply, socket}
  end

  # --- Presence Handlers ---

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    players =
      Presence.list(@presence_topic)
      |> Enum.reject(fn {id, _} -> id == socket.assigns.player_id end)
      |> Enum.map(fn {_id, %{metas: [meta | _]}} ->
        %{
          name: meta.name,
          color: meta.color,
          x: meta.camera.x,
          y: meta.camera.y,
          z: meta.camera.z
        }
      end)

    socket = push_event(socket, "players_update", %{players: players})
    {:noreply, socket}
  end

  # --- Admin Handlers ---

  @impl true
  def handle_info(:world_reset, socket) do
    socket = push_event(socket, "world_reset", %{})
    {:noreply, socket}
  end

  # --- Helpers ---

  defp build_face_terrain(face_id, subdivisions) do
    for row <- 0..(subdivisions - 1) do
      for col <- 0..(subdivisions - 1) do
        tile = WorldStore.get_tile({face_id, row, col})

        resource_type =
          case tile.resource do
            nil -> nil
            {type, _amount} -> Atom.to_string(type)
          end

        %{t: Atom.to_string(tile.terrain), r: resource_type}
      end
    end
  end

  defp refresh_research(socket) do
    world_id = socket.assigns.world_id
    player_id = socket.assigns.player_id

    if world_id do
      research_summary = Research.progress_summary(world_id, player_id)
      clearance = Research.clearance_level(player_id)
      unlocked = Research.unlocked_buildings(player_id)

      socket =
        socket
        |> assign(:research_summary, research_summary)
        |> assign(:clearance_level, clearance)
        |> assign(:building_types, unlocked)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp direction_label(0), do: "W"
  defp direction_label(1), do: "S"
  defp direction_label(2), do: "E"
  defp direction_label(3), do: "N"

  defp build_tile_info({face, row, col} = key) do
    tile = WorldStore.get_tile(key)
    building = WorldStore.get_building(key)

    {resource_type, resource_amount} =
      case tile do
        %{resource: {type, amount}} -> {Atom.to_string(type), amount}
        _ -> {nil, nil}
      end

    altered_item = AlteredItems.get(key)
    corruption = Hiss.corruption_at(key)
    territory = Territory.territory_at(key)

    territory_info =
      if territory do
        owner_name = Persistence.get_player_name(territory.owner_id)
        %{owner_id: territory.owner_id, owner_name: owner_name || "Unknown"}
      else
        nil
      end

    base = %{
      face: face,
      row: row,
      col: col,
      terrain: Atom.to_string(tile.terrain),
      resource: tile.resource,
      resource_type: resource_type,
      resource_amount: resource_amount,
      building: building,
      altered_item: altered_item,
      corruption: corruption,
      territory: territory_info
    }

    if building do
      owner_name = Persistence.get_player_name(building[:owner_id])

      Map.merge(base, %{
        building_name: Lore.display_name(building.type),
        building_orientation: building.orientation,
        building_status: building_status_text(building),
        building_owner_id: building[:owner_id],
        building_owner_name: owner_name
      })
    else
      Map.merge(base, %{
        building_name: nil,
        building_orientation: nil,
        building_status: nil,
        building_owner_id: nil,
        building_owner_name: nil
      })
    end
  end

  defp building_status_text(%{type: :miner, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:progress] > 0 -> "Extracting... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  defp building_status_text(%{type: :smelter, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:input_buffer] != nil -> "Processing... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  defp building_status_text(%{type: :conveyor, state: state}) do
    if state[:item], do: "Carrying: #{Lore.display_name(state.item)}", else: "Empty"
  end

  defp building_status_text(%{type: :conveyor_mk2, state: state}) do
    count = if(state[:item], do: 1, else: 0) + if state[:buffer], do: 1, else: 0
    if count > 0, do: "Carrying: #{count}/2 items", else: "Empty"
  end

  defp building_status_text(%{type: :conveyor_mk3, state: state}) do
    count =
      if(state[:item], do: 1, else: 0) + if(state[:buffer1], do: 1, else: 0) +
        if state[:buffer2], do: 1, else: 0

    if count > 0, do: "Carrying: #{count}/3 items", else: "Empty"
  end

  defp building_status_text(%{type: :assembler, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)}"

      state[:input_a] != nil and state[:input_b] != nil ->
        "Fabricating... #{state.progress}/#{state.rate}"

      state[:input_a] != nil ->
        "Input A: #{Lore.display_name(state.input_a)} (awaiting B)"

      state[:input_b] != nil ->
        "Input B: #{Lore.display_name(state.input_b)} (awaiting A)"

      true ->
        "Idle"
    end
  end

  defp building_status_text(%{type: :refinery, state: state}) do
    cond do
      state[:output_buffer] != nil -> "Output: #{Lore.display_name(state.output_buffer)}"
      state[:input_buffer] != nil -> "Distilling... #{state.progress}/#{state.rate}"
      true -> "Idle"
    end
  end

  defp building_status_text(%{type: :submission_terminal, state: state}) do
    cond do
      state[:input_buffer] != nil ->
        "Receiving: #{Lore.display_name(state.input_buffer)}"

      state[:last_submitted] != nil ->
        "Last: #{Lore.display_name(state.last_submitted)} (#{state.total_submitted} total)"

      true ->
        "Awaiting submissions"
    end
  end

  defp building_status_text(%{type: :containment_trap, state: state}) do
    cond do
      state[:capturing] != nil ->
        "Containing... #{state.capture_progress}/15"

      true ->
        "Scanning for entities"
    end
  end

  defp building_status_text(%{type: :purification_beacon, state: state}) do
    "Active — Radius #{state[:radius] || 5}"
  end

  defp building_status_text(%{type: :defense_turret, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)} (#{state[:kills] || 0} kills)"

      (state[:kills] || 0) > 0 ->
        "Scanning — #{state.kills} kills"

      true ->
        "Scanning for hostiles"
    end
  end

  defp building_status_text(%{type: :claim_beacon, state: state}) do
    "Active — Radius #{state[:radius] || 8}"
  end

  defp building_status_text(%{type: :storage_container, state: state}) do
    if state[:item_type] do
      "#{Lore.display_name(state.item_type)}: #{state.count}/#{state.capacity}"
    else
      "Empty — 0/#{state[:capacity] || 100}"
    end
  end

  defp building_status_text(%{type: :underground_conduit, state: state}) do
    cond do
      state[:item] != nil -> "Carrying: #{Lore.display_name(state.item)}"
      state[:linked_to] != nil -> "Linked to #{format_building_key(state.linked_to)}"
      true -> "Unlinked — select another conduit to pair"
    end
  end

  defp building_status_text(%{type: :crossover, state: state}) do
    h = if state[:horizontal], do: Lore.display_name(state.horizontal), else: nil
    v = if state[:vertical], do: Lore.display_name(state.vertical), else: nil

    case {h, v} do
      {nil, nil} -> "Empty"
      {h, nil} -> "H: #{h}"
      {nil, v} -> "V: #{v}"
      {h, v} -> "H: #{h} | V: #{v}"
    end
  end

  defp building_status_text(%{type: :balancer, state: state}) do
    cond do
      state[:item] != nil -> "Routing: #{Lore.display_name(state.item)}"
      true -> "Idle — balancing output"
    end
  end

  defp building_status_text(%{type: :trade_terminal, state: state}) do
    cond do
      state[:output_buffer] != nil ->
        "Output: #{Lore.display_name(state.output_buffer)}"

      state[:trade_id] != nil ->
        "Linked — #{state.total_sent} sent, #{state.total_received} received"

      true ->
        "No requisition linked"
    end
  end

  defp building_status_text(%{type: :dimensional_stabilizer, state: state}) do
    "Active — Immunity Radius #{state[:radius] || 15}"
  end

  defp building_status_text(%{type: :astral_projection_chamber, state: _state}) do
    "Ready — Click to project"
  end

  defp building_status_text(_building), do: nil

  defp creature_boost_label(type) do
    case Creatures.boost_info(type) do
      nil -> ""
      %{type: :speed, amount: amt} -> "Speed +#{round(amt * 100)}%"
      %{type: :efficiency, amount: amt} -> "Efficiency +#{round(amt * 100)}%"
      %{type: :output, amount: amt} -> "Output +#{round(amt * 100)}%"
      %{type: :area, amount: amt} -> "Area +#{round(amt * 100)}%"
      %{type: :defense, amount: _amt} -> "Defense"
      %{type: :all, amount: amt} -> "All +#{round(amt * 100)}%"
      _ -> ""
    end
  end

  defp world_event_label(:hiss_surge), do: "ALERT: Hiss Surge Active"
  defp world_event_label(:meteor_shower), do: "EVENT: Meteor Shower"
  defp world_event_label(:resonance_cascade), do: "EVENT: Resonance Cascade"
  defp world_event_label(:entity_migration), do: "EVENT: Entity Migration"
  defp world_event_label(_), do: "EVENT: Unknown"

  defp shift_phase_label(:dawn), do: "Dawn Shift"
  defp shift_phase_label(:zenith), do: "Zenith Shift"
  defp shift_phase_label(:dusk), do: "Dusk Shift"
  defp shift_phase_label(:nadir), do: "Nadir Shift"
  defp shift_phase_label(_), do: "Unknown Shift"

  defp shift_phase_color(:dawn), do: "var(--fbc-highlight)"
  defp shift_phase_color(:zenith), do: "var(--fbc-info)"
  defp shift_phase_color(:dusk), do: "var(--fbc-accent)"
  defp shift_phase_color(:nadir), do: "#6688AA"
  defp shift_phase_color(_), do: "var(--fbc-text-dim)"

  defp trade_status_color("open"), do: "var(--fbc-info)"
  defp trade_status_color("accepted"), do: "var(--fbc-highlight)"
  defp trade_status_color("completed"), do: "var(--fbc-success)"
  defp trade_status_color("cancelled"), do: "var(--fbc-accent)"
  defp trade_status_color(_), do: "var(--fbc-text-dim)"

  defp format_building_key({face, row, col}), do: "F#{face} R#{row} C#{col}"
  defp format_building_key(_), do: "—"

  defp restore_player(params) do
    player_id =
      case params["player_id"] do
        id when is_binary(id) and id != "" -> id
        _ -> "player:#{Base.encode16(:crypto.strong_rand_bytes(8))}"
      end

    player_name =
      case params["player_name"] do
        name when is_binary(name) and name != "" -> name
        _ -> Presence.random_name()
      end

    player_color =
      case params["player_color"] do
        color when is_binary(color) and color != "" -> color
        _ -> Presence.random_color()
      end

    camera = %{
      x: to_float(params["camera_x"], 0.0),
      y: to_float(params["camera_y"], 0.0),
      z: to_float(params["camera_z"], 3.5),
      tx: to_float(params["camera_tx"], 0.0),
      ty: to_float(params["camera_ty"], 0.0),
      tz: to_float(params["camera_tz"], 0.0)
    }

    {player_id, player_name, player_color, camera}
  end

  defp to_float(val, _default) when is_float(val), do: val
  defp to_float(val, _default) when is_integer(val), do: val * 1.0
  defp to_float(nil, default), do: default
  defp to_float(_, default), do: default

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp build_buildings_snapshot do
    for face_id <- 0..29,
        {{f, r, c}, building} <- WorldStore.get_face_buildings(face_id) do
      %{
        face: f,
        row: r,
        col: c,
        type: Atom.to_string(building.type),
        orientation: building.orientation
      }
    end
  end
end
