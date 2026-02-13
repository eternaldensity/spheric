defmodule Spheric.Geometry.AdjacencyTest do
  use ExUnit.Case, async: true

  alias Spheric.Geometry.Adjacency

  describe "adjacency_map/0" do
    test "returns a map with 30 entries (one per face)" do
      map = Adjacency.adjacency_map()
      assert map_size(map) == 30
    end

    test "each face has exactly 4 neighbors" do
      map = Adjacency.adjacency_map()

      for {face_id, neighbors} <- map do
        non_nil = Enum.reject(neighbors, &is_nil/1)

        assert length(non_nil) == 4,
               "Face #{face_id} has #{length(non_nil)} neighbors (expected 4)"
      end
    end

    test "adjacency is symmetric (if A neighbors B, then B neighbors A)" do
      map = Adjacency.adjacency_map()

      for {face_id, neighbors} <- map do
        for %{face: neighbor_face} <- Enum.reject(neighbors, &is_nil/1) do
          neighbor_neighbors = Map.get(map, neighbor_face, [])

          assert Enum.any?(neighbor_neighbors, fn
                   %{face: f} -> f == face_id
                   nil -> false
                 end),
                 "Face #{face_id} neighbors #{neighbor_face}, but not vice versa"
        end
      end
    end

    test "no face is its own neighbor" do
      map = Adjacency.adjacency_map()

      for {face_id, neighbors} <- map do
        for %{face: neighbor_face} <- Enum.reject(neighbors, &is_nil/1) do
          assert neighbor_face != face_id,
                 "Face #{face_id} is listed as its own neighbor"
        end
      end
    end

    test "total unique neighbor pairs equals 60 (one per edge)" do
      map = Adjacency.adjacency_map()

      pairs =
        for {face_id, neighbors} <- map,
            %{face: neighbor_face} <- Enum.reject(neighbors, &is_nil/1) do
          {min(face_id, neighbor_face), max(face_id, neighbor_face)}
        end
        |> Enum.uniq()

      assert length(pairs) == 60
    end
  end

  describe "face_edges/1" do
    test "returns 4 edges for a face" do
      edges = Adjacency.face_edges([0, 12, 2, 14])
      assert length(edges) == 4
      assert edges == [{0, 12}, {12, 2}, {2, 14}, {14, 0}]
    end
  end
end
