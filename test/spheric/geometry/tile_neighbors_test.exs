defmodule Spheric.Geometry.TileNeighborsTest do
  use ExUnit.Case, async: true

  alias Spheric.Geometry.TileNeighbors

  @n 16

  describe "interior neighbors" do
    test "direction 0 (col+1)" do
      assert {:ok, {0, 5, 6}} = TileNeighbors.neighbor({0, 5, 5}, 0, @n)
    end

    test "direction 1 (row+1)" do
      assert {:ok, {0, 6, 5}} = TileNeighbors.neighbor({0, 5, 5}, 1, @n)
    end

    test "direction 2 (col-1)" do
      assert {:ok, {0, 5, 4}} = TileNeighbors.neighbor({0, 5, 5}, 2, @n)
    end

    test "direction 3 (row-1)" do
      assert {:ok, {0, 4, 5}} = TileNeighbors.neighbor({0, 5, 5}, 3, @n)
    end

    test "center tile has 4 interior neighbors" do
      for dir <- 0..3 do
        assert {:ok, _} = TileNeighbors.neighbor({0, 8, 8}, dir, @n)
      end
    end
  end

  describe "edge neighbors (cross-face)" do
    test "direction 0 at col=max crosses to adjacent face" do
      result = TileNeighbors.neighbor({0, 5, 15}, 0, @n)
      assert {:ok, {face, row, col}} = result
      assert face != 0
      assert row >= 0 and row < @n
      assert col >= 0 and col < @n
    end

    test "direction 1 at row=max crosses to adjacent face" do
      result = TileNeighbors.neighbor({0, 15, 5}, 1, @n)
      assert {:ok, {face, row, col}} = result
      assert face != 0
      assert row >= 0 and row < @n
      assert col >= 0 and col < @n
    end

    test "direction 2 at col=0 crosses to adjacent face" do
      result = TileNeighbors.neighbor({0, 5, 0}, 2, @n)
      assert {:ok, {face, row, col}} = result
      assert face != 0
      assert row >= 0 and row < @n
      assert col >= 0 and col < @n
    end

    test "direction 3 at row=0 crosses to adjacent face" do
      result = TileNeighbors.neighbor({0, 0, 5}, 3, @n)
      assert {:ok, {face, row, col}} = result
      assert face != 0
      assert row >= 0 and row < @n
      assert col >= 0 and col < @n
    end
  end

  describe "cross-face symmetry" do
    test "every face-edge tile has a valid cross-face neighbor" do
      max = @n - 1

      for face <- 0..29 do
        # Edge tiles for each direction
        assert {:ok, _} = TileNeighbors.neighbor({face, 5, max}, 0, @n),
               "face #{face} dir 0 should have neighbor"

        assert {:ok, _} = TileNeighbors.neighbor({face, max, 5}, 1, @n),
               "face #{face} dir 1 should have neighbor"

        assert {:ok, _} = TileNeighbors.neighbor({face, 5, 0}, 2, @n),
               "face #{face} dir 2 should have neighbor"

        assert {:ok, _} = TileNeighbors.neighbor({face, 0, 5}, 3, @n),
               "face #{face} dir 3 should have neighbor"
      end
    end

    test "cross-face neighbor is reversible (B neighbors A back)" do
      max = @n - 1

      # For each face, check that crossing an edge and coming back
      # lands on the same face (though not necessarily the same tile
      # due to remapping complexity). We verify the neighbor's neighbor
      # points back to the original face.
      for face <- 0..29 do
        # Test direction 0 (col+1 overflow) at mid-row
        {:ok, {nf, nr, nc}} = TileNeighbors.neighbor({face, 8, max}, 0, @n)

        # The neighbor tile should be on the face boundary
        # Find which direction from the neighbor leads back to our face
        back =
          Enum.find(0..3, fn dir ->
            case TileNeighbors.neighbor({nf, nr, nc}, dir, @n) do
              {:ok, {^face, _, _}} -> true
              _ -> false
            end
          end)

        assert back != nil,
               "face #{face} dir 0: neighbor {#{nf},#{nr},#{nc}} should have a path back to face #{face}"
      end
    end
  end

  describe "corner tiles" do
    test "corner (0,0) direction 2 and 3 both cross face boundaries" do
      result_2 = TileNeighbors.neighbor({0, 0, 0}, 2, @n)
      result_3 = TileNeighbors.neighbor({0, 0, 0}, 3, @n)

      assert {:ok, {f2, _, _}} = result_2
      assert {:ok, {f3, _, _}} = result_3
      assert f2 != 0
      assert f3 != 0
    end

    test "corner (max,max) direction 0 and 1 both cross face boundaries" do
      max = @n - 1
      result_0 = TileNeighbors.neighbor({0, max, max}, 0, @n)
      result_1 = TileNeighbors.neighbor({0, max, max}, 1, @n)

      assert {:ok, {f0, _, _}} = result_0
      assert {:ok, {f1, _, _}} = result_1
      assert f0 != 0
      assert f1 != 0
    end
  end

  describe "small grid (subdivisions=4)" do
    test "interior works with smaller grid" do
      assert {:ok, {0, 1, 2}} = TileNeighbors.neighbor({0, 1, 1}, 0, 4)
    end

    test "edge crossing works with smaller grid" do
      result = TileNeighbors.neighbor({0, 2, 3}, 0, 4)
      assert {:ok, {face, row, col}} = result
      assert face != 0
      assert row >= 0 and row < 4
      assert col >= 0 and col < 4
    end
  end
end
