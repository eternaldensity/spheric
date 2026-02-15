defmodule Spheric.Game.TradingTest do
  use Spheric.DataCase, async: false

  alias Spheric.Game.Trading
  alias Spheric.Game.Schema.World

  @player1 "player:trader1"
  @player2 "player:trader2"

  setup do
    Trading.init()
    Trading.clear()

    # Create a real world record for the foreign key
    {:ok, world} =
      %World{}
      |> World.changeset(%{name: "trade-test-#{System.unique_integer()}", seed: 42})
      |> Repo.insert()

    on_exit(fn ->
      Trading.clear()
    end)

    %{world_id: world.id}
  end

  describe "create_trade/4" do
    test "creates a trade with valid items", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      assert trade.offerer_id == @player1
      assert trade.status == "open"
      assert trade.offered_items == %{"iron_ingot" => 10}
      assert trade.requested_items == %{"copper_ingot" => 5}
      assert trade.offered_filled == %{}
      assert trade.requested_filled == %{}
    end

    test "rejects empty offered items", %{world_id: world_id} do
      assert {:error, :empty_trade} =
               Trading.create_trade(world_id, @player1, %{}, %{"copper_ingot" => 5})
    end

    test "rejects empty requested items", %{world_id: world_id} do
      assert {:error, :empty_trade} =
               Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{})
    end

    test "trade is retrievable after creation", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      retrieved = Trading.get_trade(trade.id)
      assert retrieved.id == trade.id
      assert retrieved.status == "open"
    end

    test "trade appears in open_trades list", %{world_id: world_id} do
      {:ok, _trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      open = Trading.open_trades(world_id)
      assert length(open) == 1
    end
  end

  describe "accept_trade/2" do
    test "accepts an open trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      {:ok, accepted} = Trading.accept_trade(trade.id, @player2)
      assert accepted.status == "accepted"
      assert accepted.accepter_id == @player2
    end

    test "rejects accepting own trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      assert {:error, :cannot_accept_own} = Trading.accept_trade(trade.id, @player1)
    end

    test "rejects accepting non-open trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      Trading.accept_trade(trade.id, @player2)
      assert {:error, :not_open} = Trading.accept_trade(trade.id, "player:third")
    end

    test "rejects accepting nonexistent trade" do
      assert {:error, :not_found} = Trading.accept_trade(999_999, @player2)
    end
  end

  describe "submit_item/3" do
    setup %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 2}, %{"copper_ingot" => 1})

      {:ok, accepted} = Trading.accept_trade(trade.id, @player2)
      %{trade: accepted}
    end

    test "offerer submits their offered item", %{trade: trade} do
      {:ok, updated} = Trading.submit_item(trade.id, @player1, :iron_ingot)
      filled = updated.offered_filled
      assert Map.get(filled, "iron_ingot") == 1
    end

    test "accepter submits requested item", %{trade: trade} do
      {:ok, updated} = Trading.submit_item(trade.id, @player2, :copper_ingot)
      filled = updated.requested_filled
      assert Map.get(filled, "copper_ingot") == 1
    end

    test "completes trade when both sides are filled", %{trade: trade} do
      {:ok, _} = Trading.submit_item(trade.id, @player1, :iron_ingot)
      {:ok, _} = Trading.submit_item(trade.id, @player1, :iron_ingot)
      {:completed, completed} = Trading.submit_item(trade.id, @player2, :copper_ingot)

      assert completed.status == "completed"
    end

    test "rejects non-participant submission", %{trade: trade} do
      assert {:error, :not_participant} = Trading.submit_item(trade.id, "player:outsider", :iron_ingot)
    end

    test "rejects item not needed by trade", %{trade: trade} do
      assert {:error, :item_not_needed} = Trading.submit_item(trade.id, @player1, :gold_ingot)
    end

    test "rejects submission on non-accepted trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 1}, %{"copper_ingot" => 1})

      assert {:error, :not_accepted} = Trading.submit_item(trade.id, @player1, :iron_ingot)
    end

    test "rejects submission on nonexistent trade" do
      assert {:error, :not_found} = Trading.submit_item(999_999, @player1, :iron_ingot)
    end
  end

  describe "cancel_trade/2" do
    test "offerer can cancel open trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      {:ok, cancelled} = Trading.cancel_trade(trade.id, @player1)
      assert cancelled.status == "cancelled"
    end

    test "offerer can cancel accepted trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      Trading.accept_trade(trade.id, @player2)

      {:ok, cancelled} = Trading.cancel_trade(trade.id, @player1)
      assert cancelled.status == "cancelled"
    end

    test "non-offerer cannot cancel trade", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 10}, %{"copper_ingot" => 5})

      assert {:error, :cannot_cancel} = Trading.cancel_trade(trade.id, @player2)
    end
  end

  describe "player_trades/2" do
    test "returns trades involving the player", %{world_id: world_id} do
      {:ok, _} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 1}, %{"copper_ingot" => 1})

      {:ok, _} =
        Trading.create_trade(world_id, @player2, %{"wire" => 1}, %{"plate" => 1})

      p1_trades = Trading.player_trades(world_id, @player1)
      assert length(p1_trades) == 1
    end

    test "includes trades where player is accepter", %{world_id: world_id} do
      {:ok, trade} =
        Trading.create_trade(world_id, @player1, %{"iron_ingot" => 1}, %{"copper_ingot" => 1})

      Trading.accept_trade(trade.id, @player2)

      p2_trades = Trading.player_trades(world_id, @player2)
      assert length(p2_trades) == 1
    end
  end
end
