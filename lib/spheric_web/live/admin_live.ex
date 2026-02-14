defmodule SphericWeb.AdminLive do
  use SphericWeb, :live_view

  alias Spheric.Game.WorldServer
  alias SphericWeb.Presence

  @presence_topic "game:presence"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spheric.PubSub, "world:admin")
      Phoenix.PubSub.subscribe(Spheric.PubSub, @presence_topic)
    end

    world_info = WorldServer.world_info()
    player_count = Presence.list(@presence_topic) |> map_size()

    socket =
      socket
      |> assign(:page_title, "SPHERIC // ADMIN")
      |> assign(:world_info, world_info)
      |> assign(:player_count, player_count)
      |> assign(:new_seed, Integer.to_string(world_info.seed))
      |> assign(:confirm_reset, false)
      |> assign(:reset_status, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; background: var(--fbc-bg); color: var(--fbc-text); font-family: 'Courier New', monospace; padding: 40px;">
      <div style="max-width: 600px; margin: 0 auto;">
        <%!-- Header --%>
        <div style="border-bottom: 2px solid var(--fbc-accent); padding-bottom: 16px; margin-bottom: 32px;">
          <div style="font-size: 10px; color: var(--fbc-text-dim); text-transform: uppercase; letter-spacing: 0.15em;">
            Federal Bureau of Control
          </div>
          <h1 style="font-size: 24px; color: var(--fbc-text-bright); margin: 8px 0 0 0; text-transform: uppercase; letter-spacing: 0.1em;">
            Administrative Terminal
          </h1>
          <div style="font-size: 11px; color: var(--fbc-text-dim); margin-top: 4px;">
            <a href="/" style="color: var(--fbc-accent); text-decoration: none;">
              &larr; Return to Operations
            </a>
          </div>
        </div>

        <%!-- World Overview --%>
        <div style="border: 1px solid var(--fbc-border); padding: 20px; margin-bottom: 24px; background: var(--fbc-panel);">
          <div style="font-size: 10px; color: var(--fbc-accent); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-border); padding-bottom: 8px;">
            World Status Report
          </div>
          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">World ID</span>
              <br />
              <span style="color: var(--fbc-highlight);">{@world_info.world_id}</span>
            </div>
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">Seed</span>
              <br />
              <span style="color: var(--fbc-highlight);">{@world_info.seed}</span>
            </div>
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">Tick</span>
              <br />
              <span style="color: var(--fbc-info);">{@world_info.tick}</span>
            </div>
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">Tiles</span>
              <br />
              <span style="color: var(--fbc-info);">{@world_info.tile_count}</span>
            </div>
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">Buildings</span>
              <br />
              <span style="color: var(--fbc-info);">{@world_info.building_count}</span>
            </div>
            <div>
              <span style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase;">Operators Online</span>
              <br />
              <span style="color: var(--fbc-success);">{@player_count}</span>
            </div>
          </div>
        </div>

        <%!-- Reset Controls --%>
        <div style="border: 1px solid var(--fbc-accent-dim); padding: 20px; background: var(--fbc-panel);">
          <div style="font-size: 10px; color: var(--fbc-accent); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 12px; border-bottom: 1px solid var(--fbc-accent-dim); padding-bottom: 8px;">
            World Reset Protocol
          </div>

          <div style="margin-bottom: 16px;">
            <label style="color: var(--fbc-text-dim); font-size: 10px; text-transform: uppercase; display: block; margin-bottom: 4px;">
              New Seed Value
            </label>
            <form phx-change="update_seed" style="display: inline;">
              <input
                type="number"
                name="seed"
                value={@new_seed}
                style="background: rgba(0,0,0,0.4); border: 1px solid var(--fbc-border); color: var(--fbc-text-bright); padding: 6px 10px; font-family: 'Courier New', monospace; font-size: 14px; width: 200px;"
              />
            </form>
          </div>

          <div
            :if={@reset_status}
            style="margin-bottom: 12px; padding: 8px; border: 1px solid var(--fbc-success); color: var(--fbc-success); font-size: 11px;"
          >
            {@reset_status}
          </div>

          <div :if={!@confirm_reset}>
            <button
              phx-click="initiate_reset"
              style="padding: 8px 20px; border: 1px solid var(--fbc-accent); background: rgba(136,34,34,0.15); color: var(--fbc-accent); cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em;"
            >
              Initiate World Reset
            </button>
          </div>

          <div
            :if={@confirm_reset}
            style="padding: 12px; border: 1px solid var(--fbc-accent); background: rgba(136,34,34,0.1);"
          >
            <div style="color: var(--fbc-accent); font-size: 12px; margin-bottom: 12px;">
              WARNING: This will permanently destroy all world data.
              All {@player_count} connected operator(s) will be disconnected.
              Confirm reset with seed {@new_seed}?
            </div>
            <div style="display: flex; gap: 12px;">
              <button
                phx-click="confirm_reset"
                style="padding: 8px 20px; border: 1px solid var(--fbc-accent); background: var(--fbc-accent); color: #fff; cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase;"
              >
                Confirm Reset
              </button>
              <button
                phx-click="cancel_reset"
                style="padding: 8px 20px; border: 1px solid var(--fbc-border); background: transparent; color: var(--fbc-text-dim); cursor: pointer; font-family: 'Courier New', monospace; font-size: 12px; text-transform: uppercase;"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("update_seed", %{"seed" => seed}, socket) do
    {:noreply, assign(socket, :new_seed, seed)}
  end

  @impl true
  def handle_event("initiate_reset", _params, socket) do
    {:noreply, assign(socket, :confirm_reset, true)}
  end

  @impl true
  def handle_event("cancel_reset", _params, socket) do
    {:noreply, assign(socket, :confirm_reset, false)}
  end

  @impl true
  def handle_event("confirm_reset", _params, socket) do
    case Integer.parse(socket.assigns.new_seed) do
      {new_seed, ""} ->
        :ok = WorldServer.reset_world(new_seed)
        world_info = WorldServer.world_info()

        socket =
          socket
          |> assign(:world_info, world_info)
          |> assign(:confirm_reset, false)
          |> assign(:reset_status, "World reset complete. New seed: #{new_seed}")

        {:noreply, socket}

      _ ->
        socket =
          socket
          |> assign(:confirm_reset, false)
          |> assign(:reset_status, "Invalid seed value. Must be an integer.")

        {:noreply, socket}
    end
  end

  # --- PubSub ---

  @impl true
  def handle_info(:world_reset, socket) do
    world_info = WorldServer.world_info()
    {:noreply, assign(socket, :world_info, world_info)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    player_count = Presence.list(@presence_topic) |> map_size()
    {:noreply, assign(socket, :player_count, player_count)}
  end
end
