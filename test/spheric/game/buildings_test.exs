defmodule Spheric.Game.BuildingsTest do
  use ExUnit.Case, async: true

  alias Spheric.Game.Buildings

  describe "types/0" do
    test "returns all 6 building types" do
      types = Buildings.types()
      assert length(types) == 6
      assert :conveyor in types
      assert :miner in types
      assert :smelter in types
      assert :assembler in types
      assert :splitter in types
      assert :merger in types
    end
  end

  describe "valid_type?/1" do
    test "returns true for valid types" do
      for type <- Buildings.types() do
        assert Buildings.valid_type?(type), "Expected #{type} to be valid"
      end
    end

    test "returns false for invalid types" do
      refute Buildings.valid_type?(:rocket)
      refute Buildings.valid_type?(:invalid)
    end
  end

  describe "display_name/1" do
    test "returns human-readable names" do
      assert Buildings.display_name(:conveyor) == "Conveyor"
      assert Buildings.display_name(:miner) == "Miner"
      assert Buildings.display_name(:smelter) == "Smelter"
      assert Buildings.display_name(:assembler) == "Assembler"
      assert Buildings.display_name(:splitter) == "Splitter"
      assert Buildings.display_name(:merger) == "Merger"
    end
  end

  describe "can_place_on?/2" do
    test "miner requires resource tile" do
      assert Buildings.can_place_on?(:miner, %{terrain: :grassland, resource: {:iron, 200}})
      assert Buildings.can_place_on?(:miner, %{terrain: :volcanic, resource: {:copper, 100}})
    end

    test "miner cannot be placed on tile without resources" do
      refute Buildings.can_place_on?(:miner, %{terrain: :grassland, resource: nil})
    end

    test "non-miner buildings can be placed on any tile" do
      tile = %{terrain: :grassland, resource: nil}

      for type <- [:conveyor, :smelter, :assembler, :splitter, :merger] do
        assert Buildings.can_place_on?(type, tile), "Expected #{type} to be placeable"
      end
    end

    test "non-miner buildings can also go on resource tiles" do
      tile = %{terrain: :desert, resource: {:iron, 300}}

      for type <- [:conveyor, :smelter, :assembler, :splitter, :merger] do
        assert Buildings.can_place_on?(type, tile), "Expected #{type} to be placeable on resource"
      end
    end

    test "invalid type cannot be placed" do
      refute Buildings.can_place_on?(:rocket, %{terrain: :grassland, resource: nil})
    end
  end
end
