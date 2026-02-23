defmodule SphericWeb.GameLive.PanelEvents do
  @moduledoc """
  Handles toggling UI panels: research, creatures, recipes, stats, board contact, waypoints.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.{
    Creatures,
    RecipeBrowser,
    Statistics,
    BoardContact,
    TheBoard
  }

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
      |> then(fn s -> if opening, do: assign(s, :show_waypoints, false), else: s end)

    {:noreply, socket}
  end

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
      |> then(fn s -> if opening, do: assign(s, :show_waypoints, false), else: s end)

    {:noreply, socket}
  end

  def handle_event("assign_creature", params, socket) do
    %{"creature_id" => creature_id, "face" => face, "row" => row, "col" => col} = params
    building_key = {SphericWeb.GameLive.Helpers.to_int(face), SphericWeb.GameLive.Helpers.to_int(row), SphericWeb.GameLive.Helpers.to_int(col)}

    case Creatures.assign_creature(socket.assigns.player_id, creature_id, building_key) do
      :ok ->
        roster = Creatures.get_player_roster(socket.assigns.player_id)
        {:noreply, assign(socket, :creature_roster, roster)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("unassign_creature", %{"creature_id" => creature_id}, socket) do
    case Creatures.unassign_creature(socket.assigns.player_id, creature_id) do
      :ok ->
        roster = Creatures.get_player_roster(socket.assigns.player_id)
        {:noreply, assign(socket, :creature_roster, roster)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

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
      |> then(fn s -> if opening, do: assign(s, :show_waypoints, false), else: s end)

    {:noreply, socket}
  end

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
        |> assign(:show_waypoints, false)
      else
        assign(socket, :show_stats, false)
      end

    {:noreply, socket}
  end

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
        |> assign(:show_waypoints, false)
      else
        assign(socket, :show_board_contact, false)
      end

    {:noreply, socket}
  end

  def handle_event("dismiss_board_message", _params, socket) do
    {:noreply, assign(socket, :board_message, nil)}
  end

  def handle_event("activate_board_contact", _params, socket) do
    if socket.assigns.clearance_level >= 3 do
      BoardContact.activate()
      summary = BoardContact.progress_summary()

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

  def handle_event("toggle_waypoints", _params, socket) do
    opening = !socket.assigns.show_waypoints

    socket =
      if opening do
        socket
        |> assign(:show_waypoints, true)
        |> assign(:show_research, false)
        |> assign(:show_creatures, false)
        |> assign(:show_trading, false)
        |> assign(:show_recipes, false)
        |> assign(:show_stats, false)
        |> assign(:show_board_contact, false)
      else
        assign(socket, :show_waypoints, false)
      end

    {:noreply, socket}
  end

  def handle_event("save_waypoint", params, socket) do
    name = params["name"] || "Waypoint"
    face = SphericWeb.GameLive.Helpers.to_int(params["face"])
    row = SphericWeb.GameLive.Helpers.to_int(params["row"])
    col = SphericWeb.GameLive.Helpers.to_int(params["col"])

    waypoint = %{"name" => name, "face" => face, "row" => row, "col" => col}
    waypoints = socket.assigns.waypoints ++ [waypoint]

    socket =
      socket
      |> assign(:waypoints, waypoints)
      |> push_event("save_waypoints", %{waypoints: waypoints})

    {:noreply, socket}
  end

  def handle_event("delete_waypoint", %{"index" => index}, socket) do
    idx = SphericWeb.GameLive.Helpers.to_int(index)
    waypoints = List.delete_at(socket.assigns.waypoints, idx)

    socket =
      socket
      |> assign(:waypoints, waypoints)
      |> push_event("save_waypoints", %{waypoints: waypoints})

    {:noreply, socket}
  end

  def handle_event("fly_to_waypoint", params, socket) do
    face = SphericWeb.GameLive.Helpers.to_int(params["face"])
    row = SphericWeb.GameLive.Helpers.to_int(params["row"])
    col = SphericWeb.GameLive.Helpers.to_int(params["col"])

    socket = push_event(socket, "fly_to_waypoint", %{face: face, row: row, col: col})
    {:noreply, socket}
  end
end
