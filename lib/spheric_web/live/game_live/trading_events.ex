defmodule SphericWeb.GameLive.TradingEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Spheric.Game.{WorldStore, Trading}
  alias SphericWeb.GameLive.Helpers

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
        |> assign(:show_waypoints, false)
      else
        assign(socket, :show_trading, false)
      end

    {:noreply, socket}
  end

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

  def handle_event("link_trade", params, socket) do
    %{"trade_id" => trade_id_str, "face" => face, "row" => row, "col" => col} = params
    trade_id = String.to_integer(trade_id_str)
    key = {Helpers.to_int(face), Helpers.to_int(row), Helpers.to_int(col)}
    building = WorldStore.get_building(key)

    if building && building.type == :trade_terminal &&
         building.owner_id == socket.assigns.player_id do
      new_state = %{building.state | trade_id: trade_id}
      WorldStore.put_building(key, %{building | state: new_state})
      tile_info = Helpers.build_tile_info(key)
      {:noreply, assign(socket, :tile_info, tile_info)}
    else
      {:noreply, socket}
    end
  end
end
