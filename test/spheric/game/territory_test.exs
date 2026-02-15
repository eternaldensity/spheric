defmodule Spheric.Game.TerritoryTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.Territory

  @test_face 52

  setup do
    Territory.init()
    Territory.clear()

    on_exit(fn ->
      Territory.clear()
    end)

    :ok
  end

  describe "default_radius/0" do
    test "returns 8" do
      assert Territory.default_radius() == 8
    end
  end

  describe "claim/3" do
    test "successfully claims unclaimed territory" do
      assert :ok == Territory.claim(1, "player:1", {@test_face, 10, 10})
    end

    test "returns error for overlapping territory by different player" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert {:error, :territory_overlap} = Territory.claim(1, "player:2", {@test_face, 12, 12})
    end

    test "returns error for already claimed by same player" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert {:error, :already_claimed} = Territory.claim(1, "player:1", {@test_face, 12, 12})
    end

    test "allows non-overlapping claims on same face" do
      Territory.claim(1, "player:1", {@test_face, 5, 5})
      # Radius is 8, so center at 30 is far enough (distance > 16)
      assert :ok == Territory.claim(1, "player:2", {@test_face, 30, 30})
    end

    test "allows claims on different faces" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert :ok == Territory.claim(1, "player:2", {@test_face + 1, 10, 10})
    end
  end

  describe "release/1" do
    test "releases claimed territory" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert :ok == Territory.release({@test_face, 10, 10})
      assert Territory.all_territories() == []
    end
  end

  describe "territory_at/1" do
    test "returns nil for unclaimed tile" do
      assert Territory.territory_at({@test_face, 5, 5}) == nil
    end

    test "returns territory for claimed tile at center" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      territory = Territory.territory_at({@test_face, 10, 10})
      assert territory.owner_id == "player:1"
    end

    test "returns territory for tile within radius" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      territory = Territory.territory_at({@test_face, 12, 12})
      assert territory.owner_id == "player:1"
    end

    test "returns nil for tile outside radius" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert Territory.territory_at({@test_face, 25, 25}) == nil
    end
  end

  describe "can_build?/2" do
    test "returns true on unclaimed tile" do
      assert Territory.can_build?("player:1", {@test_face, 5, 5})
    end

    test "returns true on own territory" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      assert Territory.can_build?("player:1", {@test_face, 10, 10})
    end

    test "returns false on another player's territory" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      refute Territory.can_build?("player:2", {@test_face, 10, 10})
    end
  end

  describe "player_territories/1" do
    test "returns empty list for player with no territory" do
      assert Territory.player_territories("player:none") == []
    end

    test "returns territories owned by player" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      Territory.claim(1, "player:2", {@test_face + 1, 10, 10})

      p1 = Territory.player_territories("player:1")
      assert length(p1) == 1
      assert hd(p1).owner_id == "player:1"
    end
  end

  describe "all_territories/0" do
    test "returns empty list initially" do
      assert Territory.all_territories() == []
    end

    test "returns all claimed territories" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      Territory.claim(1, "player:2", {@test_face + 1, 10, 10})

      assert length(Territory.all_territories()) == 2
    end
  end

  describe "territories_on_face/1" do
    test "returns only territories on the given face" do
      Territory.claim(1, "player:1", {@test_face, 10, 10})
      Territory.claim(1, "player:2", {@test_face + 1, 10, 10})

      on_face = Territory.territories_on_face(@test_face)
      assert length(on_face) == 1
      assert hd(on_face).center_face == @test_face
    end

    test "returns empty list for face with no territories" do
      assert Territory.territories_on_face(99) == []
    end
  end

  describe "put_territory/2" do
    test "directly inserts territory into ETS" do
      territory = %{
        owner_id: "player:1",
        center_face: @test_face,
        center_row: 5,
        center_col: 5,
        radius: 8,
        world_id: 1
      }

      Territory.put_territory({@test_face, 5, 5}, territory)
      assert length(Territory.all_territories()) == 1
    end
  end
end
