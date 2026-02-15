defmodule Spheric.Game.StatisticsTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.Statistics

  @test_key {51, 5, 5}

  setup do
    Statistics.init()
    Statistics.reset()

    on_exit(fn ->
      Statistics.reset()
    end)

    :ok
  end

  describe "record_production/2" do
    test "records production for a building" do
      Statistics.record_production(@test_key, :iron_ingot)
      stats = Statistics.building_stats(@test_key)
      assert stats.produced == %{iron_ingot: 1}
    end

    test "increments on repeated calls" do
      Statistics.record_production(@test_key, :iron_ingot)
      Statistics.record_production(@test_key, :iron_ingot)
      Statistics.record_production(@test_key, :iron_ingot)

      stats = Statistics.building_stats(@test_key)
      assert stats.produced == %{iron_ingot: 3}
    end

    test "tracks multiple item types independently" do
      Statistics.record_production(@test_key, :iron_ingot)
      Statistics.record_production(@test_key, :copper_ingot)
      Statistics.record_production(@test_key, :copper_ingot)

      stats = Statistics.building_stats(@test_key)
      assert stats.produced.iron_ingot == 1
      assert stats.produced.copper_ingot == 2
    end
  end

  describe "record_consumption/2" do
    test "records consumption for a building" do
      Statistics.record_consumption(@test_key, :iron_ore)
      stats = Statistics.building_stats(@test_key)
      assert stats.consumed == %{iron_ore: 1}
    end

    test "increments on repeated calls" do
      Statistics.record_consumption(@test_key, :iron_ore)
      Statistics.record_consumption(@test_key, :iron_ore)

      stats = Statistics.building_stats(@test_key)
      assert stats.consumed == %{iron_ore: 2}
    end
  end

  describe "record_throughput/2" do
    test "records throughput for a building" do
      Statistics.record_throughput(@test_key, :iron_ingot)
      stats = Statistics.building_stats(@test_key)
      assert stats.throughput == %{iron_ingot: 1}
    end
  end

  describe "building_stats/1" do
    test "returns empty stats for building with no activity" do
      stats = Statistics.building_stats({99, 99, 99})
      assert stats == %{produced: %{}, consumed: %{}, throughput: %{}}
    end

    test "returns combined stats" do
      Statistics.record_production(@test_key, :iron_ingot)
      Statistics.record_consumption(@test_key, :iron_ore)
      Statistics.record_throughput(@test_key, :wire)

      stats = Statistics.building_stats(@test_key)
      assert stats.produced == %{iron_ingot: 1}
      assert stats.consumed == %{iron_ore: 1}
      assert stats.throughput == %{wire: 1}
    end
  end

  describe "reset/0" do
    test "clears all statistics" do
      Statistics.record_production(@test_key, :iron_ingot)
      Statistics.record_consumption(@test_key, :iron_ore)

      Statistics.reset()

      stats = Statistics.building_stats(@test_key)
      assert stats == %{produced: %{}, consumed: %{}, throughput: %{}}
    end
  end
end
