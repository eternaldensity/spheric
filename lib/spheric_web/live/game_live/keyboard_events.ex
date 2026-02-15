defmodule SphericWeb.GameLive.KeyboardEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias SphericWeb.GameLive.{
    TradingEvents,
    PanelEvents,
    HotbarEvents,
    DemolishEvents,
    BuildingEvents
  }

  def handle_event("keydown", %{"key" => "f"}, socket) do
    PanelEvents.handle_event("toggle_research", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "c"}, socket) do
    PanelEvents.handle_event("toggle_creatures", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "t"}, socket) do
    TradingEvents.handle_event("toggle_trading", %{}, socket)
  end

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

  def handle_event("keydown", %{"key" => "b"}, socket) do
    PanelEvents.handle_event("toggle_recipes", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "p"}, socket) do
    PanelEvents.handle_event("toggle_stats", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "g"}, socket) do
    PanelEvents.handle_event("toggle_board_contact", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "x"}, socket) do
    DemolishEvents.handle_event("toggle_demolish_mode", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "q"}, socket) do
    if socket.assigns.show_catalog do
      HotbarEvents.handle_event("close_catalog", %{}, socket)
    else
      HotbarEvents.handle_event("open_catalog", %{}, socket)
    end
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    cond do
      socket.assigns.show_catalog ->
        HotbarEvents.handle_event("close_catalog", %{}, socket)

      socket.assigns.selected_building_type ->
        BuildingEvents.handle_event("select_building", %{"type" => "none"}, socket)

      socket.assigns.demolish_mode ->
        DemolishEvents.handle_event("toggle_demolish_mode", %{}, socket)

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("keydown", %{"key" => key}, socket)
      when key in ["1", "2", "3", "4", "5"] do
    slot_idx = String.to_integer(key) - 1

    if socket.assigns.show_catalog do
      {:noreply, assign(socket, :catalog_target_slot, slot_idx)}
    else
      type = Enum.at(socket.assigns.hotbar, slot_idx)

      if type do
        HotbarEvents.handle_event("hotbar_select", %{"slot" => Integer.to_string(slot_idx)}, socket)
      else
        HotbarEvents.handle_event("open_catalog", %{"slot" => Integer.to_string(slot_idx)}, socket)
      end
    end
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end
end
