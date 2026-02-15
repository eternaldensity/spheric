defmodule Spheric.Game.ResearchTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.Research

  setup do
    Research.init()
    Research.clear()

    on_exit(fn ->
      Research.clear()
    end)

    :ok
  end

  describe "case_files/0" do
    test "returns all case files across all levels" do
      files = Research.case_files()
      assert is_list(files)
      assert length(files) > 0

      # Each case file has required fields
      for cf <- files do
        assert Map.has_key?(cf, :id)
        assert Map.has_key?(cf, :name)
        assert Map.has_key?(cf, :clearance)
        assert Map.has_key?(cf, :requirements)
        assert is_map(cf.requirements)
      end
    end

    test "case files span levels 1 through 8" do
      levels =
        Research.case_files()
        |> Enum.map(& &1.clearance)
        |> Enum.uniq()
        |> Enum.sort()

      assert 1 in levels
      assert 8 in levels
    end
  end

  describe "case_files_for_level/1" do
    test "returns case files for specific level" do
      l1 = Research.case_files_for_level(1)
      assert length(l1) > 0
      assert Enum.all?(l1, fn cf -> cf.clearance == 1 end)
    end

    test "returns empty list for invalid level" do
      assert Research.case_files_for_level(99) == []
    end
  end

  describe "get_case_file/1" do
    test "returns a specific case file by ID" do
      all = Research.case_files()
      first = hd(all)

      found = Research.get_case_file(first.id)
      assert found.id == first.id
      assert found.name == first.name
    end

    test "returns nil for unknown ID" do
      assert Research.get_case_file("nonexistent_file") == nil
    end
  end

  describe "clearance_level/1" do
    test "returns 0 for player with no progress" do
      assert Research.clearance_level("player:new") == 0
    end
  end

  describe "unlocked_buildings/1" do
    test "returns base buildings for new player" do
      unlocked = Research.unlocked_buildings("player:new")
      assert :conveyor in unlocked
      assert :miner in unlocked
      assert :smelter in unlocked
      assert :submission_terminal in unlocked
    end

    test "does not include level 1+ buildings for new player" do
      unlocked = Research.unlocked_buildings("player:new")
      refute :splitter in unlocked
      refute :merger in unlocked
      refute :assembler in unlocked
    end
  end

  describe "can_place?/2" do
    test "allows base buildings for any player" do
      assert Research.can_place?("player:new", :conveyor)
      assert Research.can_place?("player:new", :miner)
      assert Research.can_place?("player:new", :smelter)
    end

    test "denies advanced buildings for new player" do
      refute Research.can_place?("player:new", :assembler)
      refute Research.can_place?("player:new", :refinery)
      refute Research.can_place?("player:new", :particle_collider)
    end
  end

  describe "clearance_unlocks structure" do
    test "each clearance level defines building unlocks" do
      # Level 0 always available
      l0 = Research.unlocked_buildings("player:test")
      assert length(l0) > 0

      # Verify specific known unlocks
      assert :conveyor in l0
      assert :miner in l0
    end
  end
end
