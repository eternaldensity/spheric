defmodule Spheric.Game.ConstructionCostsTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.ConstructionCosts

  describe "cost/1" do
    test "returns cost map for buildings with costs" do
      cost = ConstructionCosts.cost(:smelter)
      assert cost == %{iron_ingot: 3}
    end

    test "returns nil for unknown building types" do
      assert ConstructionCosts.cost(:nonexistent) == nil
    end

    test "higher tier buildings cost more" do
      smelter_cost = ConstructionCosts.cost(:smelter)
      assembler_cost = ConstructionCosts.cost(:assembler)

      smelter_total = smelter_cost |> Map.values() |> Enum.sum()
      assembler_total = assembler_cost |> Map.values() |> Enum.sum()

      assert assembler_total > smelter_total
    end
  end

  describe "tier/1" do
    test "returns correct tier for known buildings" do
      assert ConstructionCosts.tier(:conveyor) == 0
      assert ConstructionCosts.tier(:miner) == 0
      assert ConstructionCosts.tier(:splitter) == 1
      assert ConstructionCosts.tier(:assembler) == 2
      assert ConstructionCosts.tier(:containment_trap) == 3
      assert ConstructionCosts.tier(:bio_generator) == 4
      assert ConstructionCosts.tier(:advanced_assembler) == 5
      assert ConstructionCosts.tier(:particle_collider) == 6
      assert ConstructionCosts.tier(:dimensional_stabilizer) == 7
      assert ConstructionCosts.tier(:board_interface) == 8
    end

    test "returns 0 for unknown building types" do
      assert ConstructionCosts.tier(:nonexistent) == 0
    end
  end

  describe "all_costs/0" do
    test "returns a map with all building costs" do
      costs = ConstructionCosts.all_costs()
      assert is_map(costs)
      assert Map.has_key?(costs, :smelter)
      assert Map.has_key?(costs, :gathering_post)
    end
  end

  describe "all_tiers/0" do
    test "returns a map with all building tiers" do
      tiers = ConstructionCosts.all_tiers()
      assert is_map(tiers)
      assert Map.has_key?(tiers, :conveyor)
      assert Map.has_key?(tiers, :board_interface)
    end
  end

  describe "always_free?/1" do
    test "returns false for buildings with costs" do
      refute ConstructionCosts.always_free?(:smelter)
      refute ConstructionCosts.always_free?(:miner)
      refute ConstructionCosts.always_free?(:gathering_post)
    end
  end

  describe "initial_construction/1" do
    test "returns construction map for buildings with costs" do
      construction = ConstructionCosts.initial_construction(:smelter)
      assert construction.required == %{iron_ingot: 3}
      assert construction.delivered == %{iron_ingot: 0}
      assert construction.complete == false
    end

    test "all required items start at 0 delivered" do
      construction = ConstructionCosts.initial_construction(:assembler)
      for {item, _count} <- construction.required do
        assert Map.get(construction.delivered, item) == 0
      end
    end
  end

  describe "construction_complete?/1" do
    test "nil construction is complete" do
      assert ConstructionCosts.construction_complete?(nil)
    end

    test "construction marked complete is complete" do
      assert ConstructionCosts.construction_complete?(%{complete: true})
    end

    test "incomplete construction is not complete" do
      construction = ConstructionCosts.initial_construction(:smelter)
      refute ConstructionCosts.construction_complete?(construction)
    end

    test "fully delivered construction is complete" do
      assert ConstructionCosts.construction_complete?(%{
        required: %{iron_ingot: 3},
        delivered: %{iron_ingot: 3}
      })
    end

    test "partially delivered is not complete" do
      refute ConstructionCosts.construction_complete?(%{
        required: %{iron_ingot: 3},
        delivered: %{iron_ingot: 1}
      })
    end
  end

  describe "needs_item?/2" do
    test "nil construction needs nothing" do
      refute ConstructionCosts.needs_item?(nil, :iron_ingot)
    end

    test "complete construction needs nothing" do
      refute ConstructionCosts.needs_item?(%{complete: true}, :iron_ingot)
    end

    test "returns true for needed item" do
      construction = ConstructionCosts.initial_construction(:smelter)
      assert ConstructionCosts.needs_item?(construction, :iron_ingot)
    end

    test "returns false for item not in recipe" do
      construction = ConstructionCosts.initial_construction(:smelter)
      refute ConstructionCosts.needs_item?(construction, :copper_ingot)
    end

    test "returns false when item is fully delivered" do
      construction = %{
        required: %{iron_ingot: 3},
        delivered: %{iron_ingot: 3},
        complete: false
      }
      refute ConstructionCosts.needs_item?(construction, :iron_ingot)
    end
  end

  describe "deliver_item/2" do
    test "nil construction returns nil" do
      assert ConstructionCosts.deliver_item(nil, :iron_ingot) == nil
    end

    test "complete construction returns unchanged" do
      construction = %{complete: true, required: %{}, delivered: %{}}
      assert ConstructionCosts.deliver_item(construction, :iron_ingot) == construction
    end

    test "delivers needed item" do
      construction = ConstructionCosts.initial_construction(:smelter)
      result = ConstructionCosts.deliver_item(construction, :iron_ingot)
      assert result.delivered.iron_ingot == 1
    end

    test "rejects item not in recipe" do
      construction = ConstructionCosts.initial_construction(:smelter)
      assert ConstructionCosts.deliver_item(construction, :copper_ingot) == nil
    end

    test "rejects item already fully delivered" do
      construction = %{
        required: %{iron_ingot: 3},
        delivered: %{iron_ingot: 3},
        complete: false
      }
      assert ConstructionCosts.deliver_item(construction, :iron_ingot) == nil
    end

    test "marks complete when last item delivered" do
      construction = %{
        required: %{iron_ingot: 3},
        delivered: %{iron_ingot: 2},
        complete: false
      }
      result = ConstructionCosts.deliver_item(construction, :iron_ingot)
      assert result.complete == true
      assert result.delivered.iron_ingot == 3
    end

    test "full delivery cycle for multi-resource building" do
      construction = ConstructionCosts.initial_construction(:miner)
      # Miner costs: iron_ingot: 2, copper_ingot: 1

      construction = ConstructionCosts.deliver_item(construction, :iron_ingot)
      refute construction.complete

      construction = ConstructionCosts.deliver_item(construction, :iron_ingot)
      refute construction.complete

      construction = ConstructionCosts.deliver_item(construction, :copper_ingot)
      assert construction.complete
    end
  end
end
