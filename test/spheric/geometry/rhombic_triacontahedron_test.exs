defmodule Spheric.Geometry.RhombicTriacontahedronTest do
  use ExUnit.Case, async: true

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @epsilon 1.0e-10

  describe "vertices/0" do
    test "returns exactly 32 vertices" do
      assert length(RT.vertices()) == 32
    end

    test "all vertices are 3-tuples of floats" do
      for {x, y, z} <- RT.vertices() do
        assert is_float(x)
        assert is_float(y)
        assert is_float(z)
      end
    end

    test "vertices are symmetric (for each vertex, its negation also exists)" do
      verts = RT.vertices()

      for {x, y, z} <- verts do
        assert Enum.any?(verts, fn {vx, vy, vz} ->
                 abs(vx + x) < @epsilon and abs(vy + y) < @epsilon and abs(vz + z) < @epsilon
               end),
               "Missing antipodal vertex for {#{x}, #{y}, #{z}}"
      end
    end
  end

  describe "faces/0" do
    test "returns exactly 30 faces" do
      assert length(RT.faces()) == 30
    end

    test "each face has exactly 4 vertices" do
      for face <- RT.faces() do
        assert length(face) == 4
      end
    end

    test "all face vertex indices are in range 0..31" do
      for face <- RT.faces(), idx <- face do
        assert idx >= 0 and idx <= 31
      end
    end

    test "each edge is shared by exactly 2 faces" do
      edge_counts =
        RT.faces()
        |> Enum.flat_map(fn [a, b, c, d] ->
          [{min(a, b), max(a, b)}, {min(b, c), max(b, c)},
           {min(c, d), max(c, d)}, {min(d, a), max(d, a)}]
        end)
        |> Enum.frequencies()

      for {edge, count} <- edge_counts do
        assert count == 2, "Edge #{inspect(edge)} appears #{count} times (expected 2)"
      end
    end

    test "total edge count is 60" do
      unique_edges =
        RT.faces()
        |> Enum.flat_map(fn [a, b, c, d] ->
          [{min(a, b), max(a, b)}, {min(b, c), max(b, c)},
           {min(c, d), max(c, d)}, {min(d, a), max(d, a)}]
        end)
        |> Enum.uniq()

      assert length(unique_edges) == 60
    end

    test "all faces have outward-pointing normals (CCW from outside)" do
      verts = RT.vertices()

      for {face, face_id} <- Enum.with_index(RT.faces()) do
        [ai, bi, _ci, di] = face
        a = elem_vec(verts, ai)
        b = elem_vec(verts, bi)
        d = elem_vec(verts, di)

        # Edge vectors from A
        e1 = vec_sub(b, a)
        e2 = vec_sub(d, a)

        # Cross product e1 x e2 should point outward (positive dot with face center)
        normal = cross(e1, e2)
        center = RT.face_center(face_id)

        dot = dot(normal, center)
        assert dot > 0, "Face #{face_id} has inward normal (dot=#{dot})"
      end
    end

    test "face vertices alternate order-5 and order-3" do
      orders = RT.vertex_orders()

      for {[a, b, c, d], face_id} <- Enum.with_index(RT.faces()) do
        assert Map.get(orders, a) == 5,
               "Face #{face_id}: vertex #{a} at position 0 should be order-5, got #{Map.get(orders, a)}"

        assert Map.get(orders, b) == 3,
               "Face #{face_id}: vertex #{b} at position 1 should be order-3, got #{Map.get(orders, b)}"

        assert Map.get(orders, c) == 5,
               "Face #{face_id}: vertex #{c} at position 2 should be order-5, got #{Map.get(orders, c)}"

        assert Map.get(orders, d) == 3,
               "Face #{face_id}: vertex #{d} at position 3 should be order-3, got #{Map.get(orders, d)}"
      end
    end
  end

  describe "vertex_orders/0" do
    test "has 12 order-5 vertices" do
      orders = RT.vertex_orders()
      count_5 = Enum.count(orders, fn {_v, order} -> order == 5 end)
      assert count_5 == 12
    end

    test "has 20 order-3 vertices" do
      orders = RT.vertex_orders()
      count_3 = Enum.count(orders, fn {_v, order} -> order == 3 end)
      assert count_3 == 20
    end

    test "order-5 vertices are indices 0..11" do
      orders = RT.vertex_orders()
      for i <- 0..11 do
        assert Map.get(orders, i) == 5, "Vertex #{i} should be order-5"
      end
    end

    test "order-3 vertices are indices 12..31" do
      orders = RT.vertex_orders()
      for i <- 12..31 do
        assert Map.get(orders, i) == 3, "Vertex #{i} should be order-3"
      end
    end
  end

  describe "normalize/2" do
    test "normalizes a point to unit sphere" do
      {x, y, z} = RT.normalize({3.0, 4.0, 0.0})
      len = :math.sqrt(x * x + y * y + z * z)
      assert_in_delta len, 1.0, @epsilon
    end

    test "normalizes to custom radius" do
      {x, y, z} = RT.normalize({3.0, 4.0, 0.0}, 2.0)
      len = :math.sqrt(x * x + y * y + z * z)
      assert_in_delta len, 2.0, @epsilon
    end

    test "preserves direction" do
      {x, y, z} = RT.normalize({3.0, 4.0, 0.0})
      assert_in_delta x, 0.6, @epsilon
      assert_in_delta y, 0.8, @epsilon
      assert_in_delta z, 0.0, @epsilon
    end
  end

  describe "client_payload/0" do
    test "returns a map with vertices, faces, and subdivisions" do
      payload = RT.client_payload()
      assert is_map(payload)
      assert Map.has_key?(payload, :vertices)
      assert Map.has_key?(payload, :faces)
      assert Map.has_key?(payload, :subdivisions)
    end

    test "vertices is a flat list of 96 floats (32 * 3)" do
      %{vertices: verts} = RT.client_payload()
      assert length(verts) == 96
      assert Enum.all?(verts, &is_float/1)
    end

    test "faces is a list of 30 four-element lists" do
      %{faces: faces} = RT.client_payload()
      assert length(faces) == 30
      assert Enum.all?(faces, fn f -> length(f) == 4 end)
    end

    test "payload is JSON-serializable" do
      payload = RT.client_payload()
      assert {:ok, _json} = Jason.encode(payload)
    end
  end

  # Vector helpers
  defp elem_vec(verts, idx), do: Enum.at(verts, idx)

  defp vec_sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}

  defp cross({ax, ay, az}, {bx, by, bz}) do
    {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
  end

  defp dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz
end
