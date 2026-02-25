defmodule SphericWeb.GameLive do
  use SphericWeb, :live_view

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  alias Spheric.Game.{
    Buildings,
    Persistence,
    Research,
    Creatures,
    Lore,
    ObjectsOfPower,
    RecipeBrowser,
    WorldEvents,
    BoardContact,
    ShiftCycle,
    StarterKit
  }

  alias SphericWeb.Presence

  alias SphericWeb.GameLive.{
    Helpers,
    ServerSync,
    BuildingEvents,
    TradingEvents,
    PanelEvents,
    HotbarEvents,
    BlueprintEvents,
    DemolishEvents,
    CameraEvents,
    KeyboardEvents
  }

  import Helpers,
    only: [
      direction_label: 1,
      creature_boost_label: 1,
      format_building_key: 1,
      trade_status_color: 1,
      world_event_label: 1,
      catalog_buildings: 2,
      shift_phase_color: 1,
      shift_phase_label: 1
    ]

  require Logger

  @presence_topic "game:presence"

  @impl true
  def mount(_params, _session, socket) do
    geometry_data = RT.client_payload()

    # Build initial buildings snapshot
    buildings_data = Helpers.build_buildings_snapshot()

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
        Helpers.restore_player(get_connect_params(socket))
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
      Phoenix.PubSub.subscribe(Spheric.PubSub, "drone:#{player_id}")
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:events")

      # Astral Projection OoP: subscribe to global creature topic
      if ObjectsOfPower.player_has?(player_id, :creature_sight) do
        Phoenix.PubSub.subscribe(Spheric.PubSub, "world:creatures")
      end
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
      |> assign(:recipes, RecipeBrowser.all_recipes() |> Enum.filter(fn r -> r.building in unlocked end))
      |> assign(:recipe_filter_building, nil)
      |> assign(:recipe_filter_name, nil)
      |> assign(:show_stats, false)
      |> assign(:stats_summary, [])
      |> assign(:blueprint_mode, nil)
      |> assign(:blueprint_count, 0)
      |> assign(:hotbar, Helpers.restore_hotbar(if(connected?(socket), do: get_connect_params(socket), else: %{}), unlocked))
      |> assign(:show_catalog, false)
      |> assign(:catalog_tab, :logistics)
      |> assign(:catalog_target_slot, nil)
      |> assign(:board_message, nil)
      |> assign(:active_event, WorldEvents.active_event())
      |> assign(:shift_phase, ShiftCycle.current_phase())
      |> assign(:show_board_contact, false)
      |> assign(:board_contact, BoardContact.progress_summary())
      |> assign(:show_waypoints, false)
      |> assign(:waypoints, Helpers.restore_waypoints(if(connected?(socket), do: get_connect_params(socket), else: %{})))
      |> assign(:demolish_mode, false)
      |> assign(:arm_linking, nil)
      |> assign(:conduit_linking, nil)
      |> assign(:starter_kit_remaining, StarterKit.get_remaining(player_id))
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

        # Send initial shift cycle lighting relative to camera position
        cam = {camera.x, camera.y, camera.z}
        local = ShiftCycle.lighting_for_camera(cam)
        {sx, sy, sz} = ShiftCycle.sun_direction()

        socket =
          push_event(socket, "shift_cycle_changed", %{
            phase: Atom.to_string(local.phase),
            ambient: local.ambient,
            directional: local.directional,
            intensity: local.intensity,
            bg: local.bg,
            sun_x: sx,
            sun_y: sy,
            sun_z: sz
          })

        # Sync drone upgrades so client localStorage stays in sync with DB
        drone_upgrades = Persistence.get_drone_upgrades(player_id)

        owned =
          drone_upgrades
          |> Enum.filter(fn {_k, v} -> v end)
          |> Enum.map(fn {k, _v} -> k end)

        socket = push_event(socket, "drone_upgrades_sync", %{upgrades: owned})

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

    <%!-- === FUEL GAUGE (bottom center, above toolbar) === --%>
    <div
      id="fuel-gauge"
      phx-update="ignore"
      style="position: fixed; bottom: 62px; left: 50%; transform: translateX(-50%); display: flex; gap: 3px; align-items: flex-end; pointer-events: none; z-index: 45;"
    >
    </div>

    <%!-- === CARGO HUD (above fuel gauge) === --%>
    <div
      id="cargo-hud"
      phx-update="ignore"
      style="position: fixed; bottom: 100px; left: 50%; transform: translateX(-50%); display: flex; gap: 3px; align-items: center; pointer-events: none; z-index: 46;"
    >
    </div>

    <%!-- === DRONE PROMPT (center screen, above cargo) === --%>
    <div
      id="drone-prompt"
      phx-update="ignore"
      style="position: fixed; bottom: 120px; left: 50%; transform: translateX(-50%); pointer-events: none; z-index: 45; font-family: 'Courier New', monospace; font-size: 11px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; opacity: 0; transition: opacity 0.2s;"
    >
    </div>

    <%!-- === LOW POWER VIGNETTE === --%>
    <div
      id="low-power-vignette"
      phx-update="ignore"
      style="position: fixed; inset: 0; pointer-events: none; z-index: 40; opacity: 0; transition: opacity 0.5s; background: radial-gradient(ellipse at center, transparent 40%, rgba(180,40,40,0.35) 100%);"
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
        :if={@tile_info[:ground_items] != nil and @tile_info.ground_items != %{}}
        style="margin-top: 4px; border-top: 1px solid var(--fbc-border); padding-top: 4px;"
      >
        <div style="color: var(--fbc-highlight); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em;">
          Ground Items
        </div>
        <div :for={{item_type, count} <- @tile_info.ground_items} style="font-size: 11px;">
          <span style="color: var(--fbc-info);">{Lore.display_name(item_type)}</span>
          <span style="color: var(--fbc-text-dim);">x{count}</span>
        </div>
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
        <div style="display: flex; align-items: center; gap: 6px; color: var(--fbc-text-dim); font-size: 11px;">
          <span>Facing: {direction_label(@tile_info.building_orientation)}</span>
          <button
            :if={@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id}
            phx-click="rotate_placed_building"
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style="padding: 2px 8px; border: 1px solid var(--fbc-border-light); background: rgba(255,255,255,0.06); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.05em;"
            title="Rotate 90°"
          >
            Rotate
          </button>
        </div>
        <div :if={@tile_info.building_status} style="color: var(--fbc-text-dim); font-size: 11px;">
          {@tile_info.building_status}
        </div>
        <div :if={@tile_info.building_owner_name} style="color: var(--fbc-text-dim); font-size: 11px;">
          Operator: <span style="color: var(--fbc-info);">{@tile_info.building_owner_name}</span>
        </div>
        <div style="display: flex; gap: 6px; margin-top: 6px;">
          <button
            :if={@tile_info.building.state[:powered] != nil and
              (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
            phx-click="toggle_power"
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style={"padding: 4px 10px; border: 1px solid #{if @tile_info.building.state[:powered], do: "var(--fbc-border-light)", else: "var(--fbc-accent-dim)"}; background: #{if @tile_info.building.state[:powered], do: "rgba(255,255,255,0.06)", else: "rgba(136,34,34,0.2)"}; color: #{if @tile_info.building.state[:powered], do: "var(--fbc-highlight)", else: "var(--fbc-accent)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em;"}
          >
            {if @tile_info.building.state[:powered], do: "ON", else: "OFF"}
          </button>
          <button
            :if={@tile_info.building.state[:output_buffer] != nil and
              (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
            phx-click="eject_output"
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style="padding: 4px 10px; border: 1px solid var(--fbc-border-light); background: rgba(255,255,255,0.06); color: var(--fbc-highlight); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em;"
          >
            Eject
          </button>
          <button
            :if={((@tile_info.building.state[:input_buffer] != nil) or
              (@tile_info.building.state[:input_a] != nil) or
              (@tile_info.building.state[:input_b] != nil) or
              (@tile_info.building.state[:input_c] != nil)) and
              (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
            phx-click="flush_inputs"
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style="padding: 4px 10px; border: 1px solid var(--fbc-border-light); background: rgba(255,255,255,0.06); color: var(--fbc-highlight); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em;"
          >
            Flush
          </button>
          <button
            :if={@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id}
            phx-click="remove_building"
            phx-value-face={@tile_info.face}
            phx-value-row={@tile_info.row}
            phx-value-col={@tile_info.col}
            style="padding: 4px 10px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.2); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em;"
          >
            Decommission
          </button>
        </div>

        <%!-- Drone Bay upgrade panel --%>
        <div
          :if={@tile_info.drone_bay_info && (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
          style="margin-top: 8px; border-top: 1px solid var(--fbc-border); padding-top: 8px;"
        >
          <div style="font-size: 10px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 6px;">
            Drone Upgrades
          </div>

          <%!-- Idle mode: show upgrade cards --%>
          <div :if={@tile_info.drone_bay_info.mode == :idle}>
            <div
              :for={{upgrade, cost} <- @tile_info.drone_bay_info.upgrade_costs}
              style={"margin-bottom: 6px; padding: 6px 8px; border: 1px solid #{if Map.get(@tile_info.drone_bay_info.player_upgrades || %{}, upgrade), do: "var(--fbc-success)", else: "var(--fbc-border)"}; background: #{if Map.get(@tile_info.drone_bay_info.player_upgrades || %{}, upgrade), do: "rgba(102,136,68,0.08)", else: "rgba(255,255,255,0.02)"};"}
            >
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="font-size: 11px; color: var(--fbc-text-bright);">
                  {Helpers.upgrade_display_name(upgrade)}
                </span>
                <span
                  :if={Map.get(@tile_info.drone_bay_info.player_upgrades || %{}, upgrade)}
                  style="font-size: 9px; color: var(--fbc-success); text-transform: uppercase;"
                >
                  Installed
                </span>
                <span
                  :if={!Map.get(@tile_info.drone_bay_info.player_upgrades || %{}, upgrade) && Spheric.Game.Behaviors.DroneBay.upgrade_clearance(upgrade) > (@tile_info.drone_bay_info.player_clearance || 0)}
                  style="font-size: 9px; color: var(--fbc-warning, #cc8844); text-transform: uppercase;"
                >
                  Clearance {Spheric.Game.Behaviors.DroneBay.upgrade_clearance(upgrade)}
                </span>
                <button
                  :if={!Map.get(@tile_info.drone_bay_info.player_upgrades || %{}, upgrade) && Spheric.Game.Behaviors.DroneBay.upgrade_clearance(upgrade) <= (@tile_info.drone_bay_info.player_clearance || 0)}
                  phx-click="select_drone_upgrade"
                  phx-value-face={@tile_info.face}
                  phx-value-row={@tile_info.row}
                  phx-value-col={@tile_info.col}
                  phx-value-upgrade={upgrade}
                  style="padding: 2px 8px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.1); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
                >
                  Install
                </button>
              </div>
              <div style="font-size: 9px; color: var(--fbc-text-dim); margin-top: 2px;">
                {Enum.map_join(cost, ", ", fn {item, qty} -> "#{qty} #{Lore.display_name(item)}" end)}
              </div>
            </div>
          </div>

          <%!-- Accepting mode: show progress --%>
          <div :if={@tile_info.drone_bay_info.mode == :accepting}>
            <div style="font-size: 11px; color: var(--fbc-highlight); margin-bottom: 4px;">
              Installing: {Helpers.upgrade_display_name(@tile_info.drone_bay_info.selected_upgrade)}
            </div>
            <div style="font-size: 10px; color: var(--fbc-text-dim); margin-bottom: 4px;">
              Feed items via conduit:
            </div>
            <div
              :for={{item, required_qty} <- @tile_info.drone_bay_info.required}
              style="font-size: 10px; margin-bottom: 2px;"
            >
              <span style={"color: #{if Map.get(@tile_info.drone_bay_info.delivered, item, 0) >= required_qty, do: "var(--fbc-success)", else: "var(--fbc-text)"}"}>
                {Lore.display_name(item)}: {Map.get(@tile_info.drone_bay_info.delivered, item, 0)}/{required_qty}
              </span>
            </div>
            <button
              phx-click="cancel_drone_upgrade"
              phx-value-face={@tile_info.face}
              phx-value-row={@tile_info.row}
              phx-value-col={@tile_info.col}
              style="margin-top: 4px; padding: 3px 8px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.15); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
            >
              Cancel
            </button>
          </div>

          <%!-- Complete mode: upgrade ready to claim (stuck recovery) --%>
          <div :if={@tile_info.drone_bay_info.mode == :complete}>
            <div style="font-size: 11px; color: var(--fbc-success); margin-bottom: 4px;">
              Upgrade ready: {Helpers.upgrade_display_name(@tile_info.drone_bay_info.selected_upgrade)}
            </div>
            <button
              phx-click="claim_drone_upgrade"
              phx-value-face={@tile_info.face}
              phx-value-row={@tile_info.row}
              phx-value-col={@tile_info.col}
              style="padding: 3px 10px; border: 1px solid var(--fbc-success); background: rgba(102,136,68,0.15); color: var(--fbc-success); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
            >
              Claim
            </button>
          </div>

          <%!-- Fuel buffer info (when auto-refuel is active) --%>
          <div
            :if={@tile_info.drone_bay_info.mode == :idle && @tile_info.drone_bay_info.fuel_buffer_count > 0}
            style="margin-top: 4px; font-size: 10px; color: var(--fbc-text-dim);"
          >
            Fuel buffer: {@tile_info.drone_bay_info.fuel_buffer_count}/5
          </div>

          <%!-- Delivery drone status (when enabled) --%>
          <div
            :if={@tile_info.drone_bay_info.delivery_drone_enabled}
            style="margin-top: 6px; padding-top: 6px; border-top: 1px solid var(--fbc-border);"
          >
            <div style="font-size: 10px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 4px;">
              Delivery Drone
            </div>
            <div style="font-size: 10px; color: var(--fbc-text-dim);">
              Status: <span style={"color: #{case @tile_info.drone_bay_info.delivery_state do; :idle -> "var(--fbc-text-dim)"; :flying_to_storage -> "var(--fbc-highlight)"; :flying_to_site -> "var(--fbc-success)"; :returning -> "var(--fbc-info)"; _ -> "var(--fbc-text-dim)"; end}"}>
                {case @tile_info.drone_bay_info.delivery_state do
                  :idle -> "Idle"
                  :flying_to_storage -> "Picking up"
                  :flying_to_site -> "Delivering"
                  :returning -> "Returning"
                  _ -> "Idle"
                end}
              </span>
            </div>
            <div style="font-size: 10px; color: var(--fbc-text-dim);">
              Fuel: {if @tile_info.drone_bay_info.delivery_fuel, do: "#{elem(@tile_info.drone_bay_info.delivery_fuel, 0)} (#{Float.round(elem(@tile_info.drone_bay_info.delivery_fuel, 1), 0)}s)", else: "Empty"}
              {if @tile_info.drone_bay_info.delivery_fuel_tank_count > 0, do: " +#{@tile_info.drone_bay_info.delivery_fuel_tank_count} reserve", else: ""}
            </div>
            <div :if={@tile_info.drone_bay_info.delivery_cargo != []} style="font-size: 10px; color: var(--fbc-text-dim);">
              Cargo: {Enum.map_join(@tile_info.drone_bay_info.delivery_cargo, ", ", &Lore.display_name/1)}
            </div>
            <div style="font-size: 9px; color: var(--fbc-text-dim); margin-top: 2px;">
              Capacity: {@tile_info.drone_bay_info.delivery_cargo_capacity} items
            </div>
          </div>
        </div>

        <%!-- Arm (Loader/Unloader) configuration panel --%>
        <div
          :if={@tile_info.arm_info && (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
          style="margin-top: 8px; border-top: 1px solid var(--fbc-border); padding-top: 8px;"
        >
          <div style="font-size: 10px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 6px;">
            Arm Configuration
          </div>

          <%!-- Source --%>
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
            <span style="font-size: 10px; color: var(--fbc-text-dim);">
              Source: <span style="color: var(--fbc-text);">
                {if @tile_info.arm_info.source, do: @tile_info.arm_info.source_label, else: "Not set"}
              </span>
            </span>
            <button
              phx-click="start_arm_link"
              phx-value-face={@tile_info.face}
              phx-value-row={@tile_info.row}
              phx-value-col={@tile_info.col}
              phx-value-mode="source"
              style="padding: 2px 8px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.1); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
            >
              Set
            </button>
          </div>

          <%!-- Destination --%>
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
            <span style="font-size: 10px; color: var(--fbc-text-dim);">
              Dest: <span style="color: var(--fbc-text);">
                {if @tile_info.arm_info.destination, do: @tile_info.arm_info.destination_label, else: "Not set"}
              </span>
            </span>
            <button
              phx-click="start_arm_link"
              phx-value-face={@tile_info.face}
              phx-value-row={@tile_info.row}
              phx-value-col={@tile_info.col}
              phx-value-mode="destination"
              style="padding: 2px 8px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.1); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
            >
              Set
            </button>
          </div>

          <%!-- Bulk transfer upgrade --%>
          <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 6px;">
            <span style="font-size: 10px; color: var(--fbc-text-dim);">
              Bulk Transfer: <span style={"color: #{if @tile_info.arm_info.stack_upgrade, do: "var(--fbc-success)", else: "var(--fbc-text-dim)"}"}>
                {if @tile_info.arm_info.stack_upgrade, do: "Active", else: "Inactive"}
              </span>
            </span>
            <button
              phx-click="upgrade_arm"
              phx-value-face={@tile_info.face}
              phx-value-row={@tile_info.row}
              phx-value-col={@tile_info.col}
              style={"padding: 2px 8px; border: 1px solid #{if @tile_info.arm_info.stack_upgrade, do: "var(--fbc-success)", else: "var(--fbc-border)"}; background: #{if @tile_info.arm_info.stack_upgrade, do: "rgba(102,136,68,0.15)", else: "rgba(255,255,255,0.06)"}; color: #{if @tile_info.arm_info.stack_upgrade, do: "var(--fbc-success)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"}
            >
              {if @tile_info.arm_info.stack_upgrade, do: "Disable", else: "Enable"}
            </button>
          </div>
        </div>

        <%!-- Underground Conduit linking panel --%>
        <div
          :if={@tile_info.conduit_info && (@tile_info.building_owner_id == nil or @tile_info.building_owner_id == @player_id)}
          style="margin-top: 8px; border-top: 1px solid var(--fbc-border); padding-top: 8px;"
        >
          <div style="font-size: 10px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 6px;">
            Conduit Link
          </div>
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <span style="font-size: 10px; color: var(--fbc-text-dim);">
              Paired: <span style={"color: #{if @tile_info.conduit_info.linked_to, do: "var(--fbc-text)", else: "var(--fbc-text-dim)"}"}>
                {if @tile_info.conduit_info.linked_to, do: @tile_info.conduit_info.linked_label, else: "None"}
              </span>
            </span>
            <div style="display: flex; gap: 4px;">
              <button
                phx-click="start_conduit_link"
                phx-value-face={@tile_info.face}
                phx-value-row={@tile_info.row}
                phx-value-col={@tile_info.col}
                style="padding: 2px 8px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.1); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
              >
                Link
              </button>
              <button
                :if={@tile_info.conduit_info.linked_to}
                phx-click="unlink_conduit"
                phx-value-face={@tile_info.face}
                phx-value-row={@tile_info.row}
                phx-value-col={@tile_info.col}
                style="padding: 2px 8px; border: 1px solid var(--fbc-accent-dim); background: rgba(136,34,34,0.15); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
              >
                Unlink
              </button>
            </div>
          </div>
        </div>

        <%!-- Linking mode indicators --%>
        <div
          :if={@arm_linking != nil}
          style="margin-top: 6px; padding: 6px 8px; border: 1px solid var(--fbc-highlight); background: rgba(204,170,102,0.1); font-size: 10px; color: var(--fbc-highlight); text-transform: uppercase; letter-spacing: 0.05em; text-align: center;"
        >
          Select a tile to set {elem(@arm_linking, 0)}...
        </div>
        <div
          :if={@conduit_linking != nil}
          style="margin-top: 6px; padding: 6px 8px; border: 1px solid var(--fbc-highlight); background: rgba(204,170,102,0.1); font-size: 10px; color: var(--fbc-highlight); text-transform: uppercase; letter-spacing: 0.05em; text-align: center;"
        >
          Select another Subsurface Link to pair...
        </div>
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
        :for={cf <- Enum.filter(@research_summary, fn cf -> cf.clearance <= @clearance_level + 2 end)}
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
          onkeydown="event.stopPropagation()"
          style="width: 100%; padding: 6px 10px; background: rgba(255,255,255,0.04); border: 1px solid var(--fbc-border); color: var(--fbc-text); font-family: 'Courier New', monospace; font-size: 11px; box-sizing: border-box;"
        />
      </form>
      <div
        :if={@recipe_filter_building}
        style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; padding: 5px 8px; background: rgba(200,170,110,0.1); border: 1px solid var(--fbc-highlight); font-size: 10px;"
      >
        <span style="color: var(--fbc-highlight);">
          Filtered: {@recipe_filter_name}
        </span>
        <button
          phx-click="clear_recipe_filter"
          style="padding: 2px 6px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.05); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase;"
        >
          Show All
        </button>
      </div>
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
            <span :if={input.count > 1}>{input.count}x </span>{input.name}
          </span>
        </div>
        <div style="font-size: 11px;">
          <span style="color: var(--fbc-text-dim);">Output:</span>
          <span style="color: var(--fbc-success); margin-left: 4px;">
            <span :if={recipe.output.count > 1}>{recipe.output.count}x </span>{recipe.output.name}
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

    <%!-- === WAYPOINTS PANEL (top-right) === --%>
    <div
      :if={@show_waypoints}
      style="position: fixed; top: 50px; right: 16px; background: var(--fbc-panel); color: var(--fbc-text); padding: 16px; font-family: 'Courier New', monospace; font-size: 12px; line-height: 1.6; pointer-events: auto; min-width: 280px; max-width: 340px; max-height: 70vh; overflow-y: auto; border: 1px solid var(--fbc-info);"
    >
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-info); padding-bottom: 8px;">
        <span style="font-size: 13px; color: var(--fbc-info); text-transform: uppercase; letter-spacing: 0.15em;">
          Waypoints
        </span>
        <span style="font-size: 10px; color: var(--fbc-text-dim); text-transform: uppercase;">
          {length(@waypoints)} saved
        </span>
      </div>

      <%!-- Save current tile as waypoint --%>
      <div :if={@tile_info} style="margin-bottom: 12px; padding: 8px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);">
        <div style="font-size: 10px; color: var(--fbc-text-dim); text-transform: uppercase; margin-bottom: 6px;">
          Save selected tile
        </div>
        <form phx-submit="save_waypoint" style="display: flex; gap: 4px; align-items: center;">
          <input type="hidden" name="face" value={@tile_info.face} />
          <input type="hidden" name="row" value={@tile_info.row} />
          <input type="hidden" name="col" value={@tile_info.col} />
          <input
            type="text"
            name="name"
            placeholder="Waypoint name..."
            required
            onkeydown="event.stopPropagation()"
            style="flex: 1; padding: 4px 8px; background: rgba(255,255,255,0.06); border: 1px solid var(--fbc-border); color: var(--fbc-text); font-family: 'Courier New', monospace; font-size: 11px;"
          />
          <button
            type="submit"
            style="padding: 4px 10px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.12); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.05em; white-space: nowrap;"
          >
            Save
          </button>
        </form>
      </div>

      <div :if={@tile_info == nil && @waypoints == []} style="color: var(--fbc-text-dim); font-size: 11px; text-align: center; padding: 16px 0;">
        Click a tile to select it, then save it as a waypoint.
      </div>

      <div :if={@tile_info == nil && @waypoints != []} style="color: var(--fbc-text-dim); font-size: 10px; margin-bottom: 8px;">
        Click a tile to save a new waypoint.
      </div>

      <%!-- Waypoint list --%>
      <div
        :for={{wp, idx} <- Enum.with_index(@waypoints)}
        style="display: flex; align-items: center; gap: 6px; padding: 6px 8px; margin-bottom: 4px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02);"
      >
        <div style="flex: 1; min-width: 0;">
          <div style="font-size: 11px; color: var(--fbc-text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
            {wp["name"]}
          </div>
          <div style="font-size: 9px; color: var(--fbc-text-dim); text-transform: uppercase;">
            Sector {wp["face"]} &middot; {wp["row"]},{wp["col"]}
          </div>
        </div>
        <button
          phx-click="fly_to_waypoint"
          phx-value-face={wp["face"]}
          phx-value-row={wp["row"]}
          phx-value-col={wp["col"]}
          style="padding: 3px 8px; border: 1px solid var(--fbc-info); background: rgba(136,153,170,0.1); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px; text-transform: uppercase; letter-spacing: 0.05em;"
        >
          Fly
        </button>
        <button
          phx-click="delete_waypoint"
          phx-value-index={idx}
          style="padding: 3px 6px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.02); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 9px;"
        >
          X
        </button>
      </div>
    </div>

    <%!-- === FULLSCREEN BUILDING CATALOG === --%>
    <div
      :if={@show_catalog}
      phx-click="close_catalog"
      style="position: fixed; inset: 0; background: rgba(5,4,3,0.85); z-index: 100; display: flex; align-items: center; justify-content: center; pointer-events: auto;"
    >
      <div
        phx-click="noop"
        style="width: min(900px, 90vw); max-height: 80vh; background: var(--fbc-panel-solid); border: 1px solid var(--fbc-border); display: flex; flex-direction: column; font-family: 'Courier New', monospace;"
      >
        <%!-- Catalog header --%>
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 14px 18px; border-bottom: 1px solid var(--fbc-border);">
          <span style="font-size: 14px; color: var(--fbc-cream); text-transform: uppercase; letter-spacing: 0.15em;">
            Building Catalog
          </span>
          <button
            phx-click="close_catalog"
            style="padding: 4px 10px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.04); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 11px; text-transform: uppercase;"
          >
            Close (Esc)
          </button>
        </div>
        <%!-- Category tabs --%>
        <div style="display: flex; gap: 0; border-bottom: 1px solid var(--fbc-border); overflow-x: auto;">
          <button
            :for={cat <- Buildings.categories()}
            phx-click="catalog_tab"
            phx-value-tab={cat}
            style={"
              padding: 10px 16px;
              border: none;
              border-bottom: 2px solid #{if @catalog_tab == cat, do: "var(--fbc-accent)", else: "transparent"};
              background: #{if @catalog_tab == cat, do: "rgba(204,51,51,0.1)", else: "transparent"};
              color: #{if @catalog_tab == cat, do: "var(--fbc-accent)", else: "var(--fbc-text-dim)"};
              cursor: pointer;
              font-family: 'Courier New', monospace;
              font-size: 11px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              white-space: nowrap;
            "}
          >
            {Buildings.category_display_name(cat)}
          </button>
        </div>
        <%!-- Building grid --%>
        <div style="padding: 16px; overflow-y: auto; flex: 1; display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 8px; align-content: start;">
          <button
            :for={type <- catalog_buildings(@catalog_tab, @building_types)}
            phx-click="catalog_select"
            phx-value-type={type}
            style={"
              padding: 10px 10px 8px;
              border: 1px solid #{if @selected_building_type == type, do: "var(--fbc-accent)", else: "var(--fbc-border)"};
              background: #{if @selected_building_type == type, do: "rgba(204,51,51,0.12)", else: "rgba(255,255,255,0.03)"};
              color: #{if @selected_building_type == type, do: "var(--fbc-accent)", else: "var(--fbc-text)"};
              cursor: pointer;
              font-family: 'Courier New', monospace;
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.05em;
              text-align: center;
            "}
          >
            <div>{Lore.display_name(type)}</div>
            <div style={"
              font-size: 9px;
              margin-top: 4px;
              text-transform: none;
              letter-spacing: 0;
              color: #{if Map.get(@starter_kit_remaining, type, 0) > 0, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"};
            "}>
              {Helpers.building_cost_label(type, @starter_kit_remaining)}
            </div>
          </button>
          <div
            :if={catalog_buildings(@catalog_tab, @building_types) == []}
            style="grid-column: 1 / -1; color: var(--fbc-text-dim); font-size: 11px; text-align: center; padding: 20px;"
          >
            No buildings unlocked in this category.
          </div>
        </div>
        <%!-- Catalog footer hint --%>
        <div
          :if={@catalog_target_slot != nil}
          style="padding: 8px 18px; border-top: 1px solid var(--fbc-border); color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em;"
        >
          Assigning to hotbar slot {@catalog_target_slot + 1}
        </div>
      </div>
    </div>

    <%!-- === BOTTOM TOOLBAR === --%>
    <div style="position: fixed; bottom: 0; left: 0; right: 0; display: flex; align-items: center; gap: 4px; padding: 8px 12px; background: var(--fbc-panel); border-top: 1px solid var(--fbc-border); pointer-events: auto; z-index: 50;">
      <%!-- Panel toggle buttons --%>
      <button
        phx-click="toggle_research"
        style={"padding: 6px 10px; border: 1px solid #{if @show_research, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @show_research, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_research, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Case Files (F)"
      >
        Files
      </button>
      <button
        phx-click="toggle_creatures"
        style={"padding: 6px 10px; border: 1px solid #{if @show_creatures, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @show_creatures, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_creatures, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Entities (C)"
      >
        Ent
      </button>
      <button
        phx-click="toggle_trading"
        style={"padding: 6px 10px; border: 1px solid #{if @show_trading, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @show_trading, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_trading, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Trades (T)"
      >
        Trade
      </button>
      <button
        phx-click="toggle_recipes"
        style={"padding: 6px 10px; border: 1px solid #{if @show_recipes, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @show_recipes, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_recipes, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Protocols (B)"
      >
        Proto
      </button>
      <button
        phx-click="toggle_stats"
        style={"padding: 6px 10px; border: 1px solid #{if @show_stats, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @show_stats, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_stats, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Report (P)"
      >
        Rpt
      </button>
      <button
        phx-click="toggle_board_contact"
        style={"padding: 6px 10px; border: 1px solid #{if @show_board_contact, do: "var(--fbc-gold)", else: "var(--fbc-border)"}; background: #{if @show_board_contact, do: "rgba(204,170,68,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_board_contact, do: "var(--fbc-gold)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Board Contact (G)"
      >
        Board
      </button>
      <button
        phx-click="toggle_waypoints"
        style={"padding: 6px 10px; border: 1px solid #{if @show_waypoints, do: "var(--fbc-info)", else: "var(--fbc-border)"}; background: #{if @show_waypoints, do: "rgba(136,153,170,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @show_waypoints, do: "var(--fbc-info)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Waypoints (W)"
      >
        Nav
      </button>
      <%!-- Blueprint buttons --%>
      <button
        phx-click="blueprint_capture"
        style={"padding: 6px 10px; border: 1px solid #{if @blueprint_mode == :capture, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @blueprint_mode == :capture, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @blueprint_mode == :capture, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Capture blueprint"
      >
        Cap
      </button>
      <button
        :if={@blueprint_count > 0}
        phx-click="blueprint_stamp"
        style={"padding: 6px 10px; border: 1px solid #{if @blueprint_mode == :stamp, do: "var(--fbc-highlight)", else: "var(--fbc-border)"}; background: #{if @blueprint_mode == :stamp, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @blueprint_mode == :stamp, do: "var(--fbc-highlight)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Stamp blueprint"
      >
        Stp
      </button>
      <button
        phx-click="toggle_demolish_mode"
        style={"padding: 6px 10px; border: 1px solid #{if @demolish_mode, do: "var(--fbc-accent)", else: "var(--fbc-border)"}; background: #{if @demolish_mode, do: "rgba(204,51,51,0.18)", else: "rgba(255,255,255,0.04)"}; color: #{if @demolish_mode, do: "var(--fbc-accent)", else: "var(--fbc-text-dim)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"}
        title="Demolish area (X)"
      >
        Dem
      </button>

      <%!-- Separator --%>
      <div style="width: 1px; height: 28px; background: var(--fbc-border); margin: 0 6px;"></div>

      <%!-- Hotbar slots --%>
      <div style="display: flex; gap: 4px; align-items: center;">
        <button
          :for={{slot_type, idx} <- Enum.with_index(@hotbar)}
          phx-click={if slot_type, do: "hotbar_select", else: "open_catalog"}
          phx-value-slot={idx}
          style={"
            width: 72px;
            padding: 6px 4px;
            border: 1px solid #{cond do
              slot_type && @selected_building_type == slot_type -> "var(--fbc-accent)"
              slot_type -> "var(--fbc-border-light)"
              true -> "var(--fbc-border)"
            end};
            background: #{cond do
              slot_type && @selected_building_type == slot_type -> "rgba(204,51,51,0.18)"
              slot_type -> "rgba(255,255,255,0.06)"
              true -> "rgba(255,255,255,0.02)"
            end};
            color: #{cond do
              slot_type && @selected_building_type == slot_type -> "var(--fbc-accent)"
              slot_type -> "var(--fbc-text)"
              true -> "var(--fbc-text-dim)"
            end};
            cursor: pointer;
            font-family: 'Courier New', monospace;
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            text-align: center;
            position: relative;
          "}
          title={"Hotbar #{idx + 1} (#{idx + 1} key)#{if slot_type, do: " — #{Helpers.building_cost_label(slot_type, @starter_kit_remaining)} — Right-click to change", else: " — Click to assign"}"}
        >
          <span style="font-size: 8px; color: var(--fbc-text-dim); position: absolute; top: 2px; left: 4px;">{idx + 1}</span>
          {if slot_type, do: Lore.display_name(slot_type), else: "+"}
        </button>
      </div>

      <%!-- Catalog open button --%>
      <button
        phx-click="open_catalog"
        style="padding: 6px 10px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.04); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;"
        title="Building Catalog (Q)"
      >
        Catalog
      </button>

      <%!-- Building placement controls (when a building is selected) --%>
      <div
        :if={@selected_building_type}
        style="display: flex; align-items: center; gap: 4px; margin-left: 4px; padding-left: 8px; border-left: 1px solid var(--fbc-border);"
      >
        <button
          phx-click="rotate_building"
          style="padding: 6px 10px; border: 1px solid var(--fbc-border-light); background: rgba(255,255,255,0.04); color: var(--fbc-info); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
          title="Rotate (R)"
        >
          {direction_label(@placement_orientation)}
        </button>
        <button
          phx-click="toggle_line_mode"
          style={"padding: 6px 10px; border: 1px solid #{if @line_mode, do: "var(--fbc-highlight)", else: "var(--fbc-border-light)"}; background: #{if @line_mode, do: "rgba(221,170,102,0.15)", else: "rgba(255,255,255,0.04)"}; color: #{if @line_mode, do: "var(--fbc-highlight)", else: "var(--fbc-info)"}; cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase; font-weight: #{if @line_mode, do: "bold", else: "normal"};"}
          title="Line mode (L)"
        >
          Line
        </button>
        <button
          phx-click="select_building"
          phx-value-type="none"
          style="padding: 6px 10px; border: 1px solid var(--fbc-border); background: rgba(255,255,255,0.04); color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 10px; text-transform: uppercase;"
        >
          Cancel
        </button>
      </div>

      <%!-- Shift cycle indicator (right-aligned) --%>
      <div style="margin-left: auto; color: var(--fbc-text); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; pointer-events: none;">
        <span style={"color: #{shift_phase_color(@shift_phase)};"}>
          {shift_phase_label(@shift_phase)}
        </span>
      </div>
    </div>
    """
  end

  # === Event Handlers (delegated to submodules) ===

  # Building events
  @impl true
  def handle_event("select_building", params, socket),
    do: BuildingEvents.handle_event("select_building", params, socket)

  @impl true
  def handle_event("rotate_building", params, socket),
    do: BuildingEvents.handle_event("rotate_building", params, socket)

  @impl true
  def handle_event("rotate_placed_building", params, socket),
    do: BuildingEvents.handle_event("rotate_placed_building", params, socket)

  @impl true
  def handle_event("toggle_line_mode", params, socket),
    do: BuildingEvents.handle_event("toggle_line_mode", params, socket)

  @impl true
  def handle_event("place_line", params, socket),
    do: BuildingEvents.handle_event("place_line", params, socket)

  @impl true
  def handle_event("tile_click", params, socket),
    do: BuildingEvents.handle_event("tile_click", params, socket)

  @impl true
  def handle_event("remove_building", params, socket),
    do: BuildingEvents.handle_event("remove_building", params, socket)

  @impl true
  def handle_event("eject_output", params, socket),
    do: BuildingEvents.handle_event("eject_output", params, socket)

  @impl true
  def handle_event("flush_inputs", params, socket),
    do: BuildingEvents.handle_event("flush_inputs", params, socket)

  @impl true
  def handle_event("toggle_power", params, socket),
    do: BuildingEvents.handle_event("toggle_power", params, socket)

  @impl true
  def handle_event("start_conduit_link", params, socket),
    do: BuildingEvents.handle_event("start_conduit_link", params, socket)

  @impl true
  def handle_event("unlink_conduit", params, socket),
    do: BuildingEvents.handle_event("unlink_conduit", params, socket)

  @impl true
  def handle_event("pickup_fuel", params, socket),
    do: BuildingEvents.handle_event("pickup_fuel", params, socket)

  @impl true
  def handle_event("drone_pickup_item", params, socket),
    do: BuildingEvents.handle_event("drone_pickup_item", params, socket)

  @impl true
  def handle_event("drone_drop_item", params, socket),
    do: BuildingEvents.handle_event("drone_drop_item", params, socket)

  @impl true
  def handle_event("select_drone_upgrade", params, socket),
    do: BuildingEvents.handle_event("select_drone_upgrade", params, socket)

  @impl true
  def handle_event("cancel_drone_upgrade", params, socket),
    do: BuildingEvents.handle_event("cancel_drone_upgrade", params, socket)

  @impl true
  def handle_event("claim_drone_upgrade", params, socket),
    do: BuildingEvents.handle_event("claim_drone_upgrade", params, socket)

  @impl true
  def handle_event("start_arm_link", params, socket),
    do: BuildingEvents.handle_event("start_arm_link", params, socket)

  @impl true
  def handle_event("upgrade_arm", params, socket),
    do: BuildingEvents.handle_event("upgrade_arm", params, socket)

  @impl true
  def handle_event("teleport_to_terminal", params, socket),
    do: BuildingEvents.handle_event("teleport_to_terminal", params, socket)

  @impl true
  def handle_event("list_terminals", params, socket),
    do: BuildingEvents.handle_event("list_terminals", params, socket)

  # Panel events
  @impl true
  def handle_event("toggle_research", params, socket),
    do: PanelEvents.handle_event("toggle_research", params, socket)

  @impl true
  def handle_event("toggle_creatures", params, socket),
    do: PanelEvents.handle_event("toggle_creatures", params, socket)

  @impl true
  def handle_event("assign_creature", params, socket),
    do: PanelEvents.handle_event("assign_creature", params, socket)

  @impl true
  def handle_event("unassign_creature", params, socket),
    do: PanelEvents.handle_event("unassign_creature", params, socket)

  @impl true
  def handle_event("toggle_recipes", params, socket),
    do: PanelEvents.handle_event("toggle_recipes", params, socket)

  @impl true
  def handle_event("recipe_search", params, socket),
    do: PanelEvents.handle_event("recipe_search", params, socket)

  @impl true
  def handle_event("toggle_stats", params, socket),
    do: PanelEvents.handle_event("toggle_stats", params, socket)

  @impl true
  def handle_event("toggle_board_contact", params, socket),
    do: PanelEvents.handle_event("toggle_board_contact", params, socket)

  @impl true
  def handle_event("dismiss_board_message", params, socket),
    do: PanelEvents.handle_event("dismiss_board_message", params, socket)

  @impl true
  def handle_event("activate_board_contact", params, socket),
    do: PanelEvents.handle_event("activate_board_contact", params, socket)

  @impl true
  def handle_event("toggle_waypoints", params, socket),
    do: PanelEvents.handle_event("toggle_waypoints", params, socket)

  @impl true
  def handle_event("save_waypoint", params, socket),
    do: PanelEvents.handle_event("save_waypoint", params, socket)

  @impl true
  def handle_event("delete_waypoint", params, socket),
    do: PanelEvents.handle_event("delete_waypoint", params, socket)

  @impl true
  def handle_event("fly_to_waypoint", params, socket),
    do: PanelEvents.handle_event("fly_to_waypoint", params, socket)

  # Trading events
  @impl true
  def handle_event("toggle_trading", params, socket),
    do: TradingEvents.handle_event("toggle_trading", params, socket)

  @impl true
  def handle_event("create_trade", params, socket),
    do: TradingEvents.handle_event("create_trade", params, socket)

  @impl true
  def handle_event("accept_trade", params, socket),
    do: TradingEvents.handle_event("accept_trade", params, socket)

  @impl true
  def handle_event("cancel_trade", params, socket),
    do: TradingEvents.handle_event("cancel_trade", params, socket)

  @impl true
  def handle_event("link_trade", params, socket),
    do: TradingEvents.handle_event("link_trade", params, socket)

  # Hotbar & catalog events
  @impl true
  def handle_event("open_catalog", params, socket),
    do: HotbarEvents.handle_event("open_catalog", params, socket)

  @impl true
  def handle_event("close_catalog", params, socket),
    do: HotbarEvents.handle_event("close_catalog", params, socket)

  @impl true
  def handle_event("catalog_tab", params, socket),
    do: HotbarEvents.handle_event("catalog_tab", params, socket)

  @impl true
  def handle_event("catalog_select", params, socket),
    do: HotbarEvents.handle_event("catalog_select", params, socket)

  @impl true
  def handle_event("hotbar_select", params, socket),
    do: HotbarEvents.handle_event("hotbar_select", params, socket)

  @impl true
  def handle_event("hotbar_clear", params, socket),
    do: HotbarEvents.handle_event("hotbar_clear", params, socket)

  @impl true
  def handle_event("noop", params, socket),
    do: HotbarEvents.handle_event("noop", params, socket)

  # Blueprint events
  @impl true
  def handle_event("blueprint_capture", params, socket),
    do: BlueprintEvents.handle_event("blueprint_capture", params, socket)

  @impl true
  def handle_event("blueprint_stamp", params, socket),
    do: BlueprintEvents.handle_event("blueprint_stamp", params, socket)

  @impl true
  def handle_event("blueprint_captured", params, socket),
    do: BlueprintEvents.handle_event("blueprint_captured", params, socket)

  @impl true
  def handle_event("blueprint_cancelled", params, socket),
    do: BlueprintEvents.handle_event("blueprint_cancelled", params, socket)

  @impl true
  def handle_event("place_blueprint", params, socket),
    do: BlueprintEvents.handle_event("place_blueprint", params, socket)

  # Demolish events
  @impl true
  def handle_event("toggle_demolish_mode", params, socket),
    do: DemolishEvents.handle_event("toggle_demolish_mode", params, socket)

  @impl true
  def handle_event("remove_area", params, socket),
    do: DemolishEvents.handle_event("remove_area", params, socket)

  # Camera events
  @impl true
  def handle_event("camera_update", params, socket),
    do: CameraEvents.handle_event("camera_update", params, socket)

  # Keyboard events
  @impl true
  def handle_event("keydown", params, socket),
    do: KeyboardEvents.handle_event("keydown", params, socket)

  # === PubSub Info Handlers (delegated to ServerSync) ===

  @impl true
  def handle_info({:building_placed, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:building_removed, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:construction_complete, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:tick_update, _, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:case_file_completed, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:research_progress, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:object_of_power_granted, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:drone_upgrade_complete, _, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:delivery_drone_update, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:creature_spawned, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:creature_moved, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:creature_captured, _, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:creature_sync, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:corruption_update, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:corruption_cleared, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:corruption_sync, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:hiss_spawned, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:hiss_moved, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:hiss_killed, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:hiss_sync, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:building_damage, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:territory_update, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:world_event_started, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:world_event_ended, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:shift_cycle_changed, _, _, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:sun_moved, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info({:creature_evolved, _, _, _} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info(:send_terrain, socket),
    do: ServerSync.handle_info(:send_terrain, socket)

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"} = msg, socket),
    do: ServerSync.handle_info(msg, socket)

  @impl true
  def handle_info(:world_reset, socket),
    do: ServerSync.handle_info(:world_reset, socket)
end
