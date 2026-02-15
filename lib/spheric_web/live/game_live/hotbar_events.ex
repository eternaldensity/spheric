defmodule SphericWeb.GameLive.HotbarEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Spheric.Game.Buildings

  def handle_event("open_catalog", params, socket) do
    target_slot =
      case params["slot"] do
        nil -> nil
        s when is_binary(s) -> String.to_integer(s)
        s when is_integer(s) -> s
      end

    socket =
      socket
      |> assign(:show_catalog, true)
      |> assign(:catalog_target_slot, target_slot)

    {:noreply, socket}
  end

  def handle_event("close_catalog", _params, socket) do
    socket =
      socket
      |> assign(:show_catalog, false)
      |> assign(:catalog_target_slot, nil)

    {:noreply, socket}
  end

  def handle_event("catalog_tab", %{"tab" => tab_str}, socket) do
    tab = String.to_existing_atom(tab_str)

    if tab in Buildings.categories() do
      {:noreply, assign(socket, :catalog_tab, tab)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("catalog_select", %{"type" => type_str}, socket) do
    type = String.to_existing_atom(type_str)

    if Buildings.valid_type?(type) do
      case socket.assigns.catalog_target_slot do
        nil ->
          socket =
            socket
            |> assign(:selected_building_type, type)
            |> assign(:blueprint_mode, nil)
            |> assign(:show_catalog, false)
            |> assign(:catalog_target_slot, nil)
            |> push_event("placement_mode", %{
              type: type_str,
              orientation: socket.assigns.placement_orientation
            })
            |> push_event("blueprint_mode", %{mode: nil})

          {:noreply, socket}

        slot_idx when is_integer(slot_idx) and slot_idx >= 0 and slot_idx < 5 ->
          hotbar = List.replace_at(socket.assigns.hotbar, slot_idx, type)

          socket =
            socket
            |> assign(:hotbar, hotbar)
            |> assign(:show_catalog, false)
            |> assign(:catalog_target_slot, nil)
            |> push_event("save_hotbar", %{hotbar: Enum.map(hotbar, fn t -> if t, do: Atom.to_string(t), else: nil end)})

          {:noreply, socket}

        _ ->
          {:noreply, assign(socket, :show_catalog, false)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("hotbar_select", %{"slot" => slot_str}, socket) do
    slot_idx = String.to_integer(slot_str)
    type = Enum.at(socket.assigns.hotbar, slot_idx)

    if type && Buildings.valid_type?(type) do
      socket =
        socket
        |> assign(:selected_building_type, type)
        |> assign(:blueprint_mode, nil)
        |> push_event("placement_mode", %{
          type: Atom.to_string(type),
          orientation: socket.assigns.placement_orientation
        })
        |> push_event("blueprint_mode", %{mode: nil})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hotbar_clear", %{"slot" => slot_str}, socket) do
    slot_idx = String.to_integer(slot_str)
    hotbar = List.replace_at(socket.assigns.hotbar, slot_idx, nil)

    socket =
      socket
      |> assign(:hotbar, hotbar)
      |> push_event("save_hotbar", %{hotbar: Enum.map(hotbar, fn t -> if t, do: Atom.to_string(t), else: nil end)})

    {:noreply, socket}
  end

  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end
end
