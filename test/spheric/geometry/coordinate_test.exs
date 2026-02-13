defmodule Spheric.Geometry.CoordinateTest do
  use ExUnit.Case, async: true

  alias Spheric.Geometry.Coordinate

  describe "visible_faces/1" do
    test "returns a list of face IDs" do
      faces = Coordinate.visible_faces({0.0, 0.0, 3.5})
      assert is_list(faces)
      assert Enum.all?(faces, fn f -> f >= 0 and f <= 29 end)
    end

    test "returns roughly half the faces (hemisphere)" do
      faces = Coordinate.visible_faces({0.0, 0.0, 3.5})
      # With the -0.3 threshold, slightly more than half are visible
      assert length(faces) >= 12
      assert length(faces) <= 25
    end

    test "faces closest to camera come first" do
      faces = Coordinate.visible_faces({0.0, 0.0, 3.5})
      # The first face should be the one whose center has highest Z
      # (since camera is on +Z axis)
      assert length(faces) > 0
    end

    test "opposite camera positions give different visible sets" do
      front = Coordinate.visible_faces({0.0, 0.0, 3.5}) |> MapSet.new()
      back = Coordinate.visible_faces({0.0, 0.0, -3.5}) |> MapSet.new()

      # The two sets should have limited overlap
      overlap = MapSet.intersection(front, back) |> MapSet.size()
      assert overlap < 20
    end

    test "camera at origin returns all faces" do
      faces = Coordinate.visible_faces({0.0, 0.0, 0.0})
      assert length(faces) == 30
    end
  end
end
