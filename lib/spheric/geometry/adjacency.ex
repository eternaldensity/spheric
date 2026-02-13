defmodule Spheric.Geometry.Adjacency do
  @moduledoc """
  Computes face adjacency for the rhombic triacontahedron.

  Two faces share an edge if they have exactly 2 vertices in common.
  Each face has exactly 4 edges and therefore 4 neighbors.

  The edges of each face are labeled by their position in the vertex list:
  - edge 0: vertices [v0, v1] (from first to second vertex)
  - edge 1: vertices [v1, v2]
  - edge 2: vertices [v2, v3]
  - edge 3: vertices [v3, v0]
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @type edge :: {non_neg_integer(), non_neg_integer()}
  @type neighbor_info :: %{
          face: non_neg_integer(),
          their_edge: non_neg_integer(),
          shared_vertices: {non_neg_integer(), non_neg_integer()}
        }

  @doc """
  Returns the adjacency map: `%{face_id => [neighbor_info]}`.

  Each face has exactly 4 neighbors (one per edge).
  The list is ordered by edge index (0, 1, 2, 3).
  """
  def adjacency_map do
    faces = RT.faces()

    # Build edge -> face mapping
    edge_to_faces =
      faces
      |> Enum.with_index()
      |> Enum.flat_map(fn {face_verts, face_id} ->
        face_edges(face_verts)
        |> Enum.with_index()
        |> Enum.map(fn {edge, edge_idx} ->
          {normalize_edge(edge), {face_id, edge_idx}}
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # For each face, find the neighbor across each edge
    faces
    |> Enum.with_index()
    |> Map.new(fn {face_verts, face_id} ->
      neighbors =
        face_edges(face_verts)
        |> Enum.with_index()
        |> Enum.map(fn {edge, _edge_idx} ->
          norm_edge = normalize_edge(edge)
          face_entries = Map.get(edge_to_faces, norm_edge, [])

          case Enum.find(face_entries, fn {fid, _} -> fid != face_id end) do
            {neighbor_face, neighbor_edge_idx} ->
              %{
                face: neighbor_face,
                their_edge: neighbor_edge_idx,
                shared_vertices: edge
              }

            nil ->
              nil
          end
        end)

      {face_id, neighbors}
    end)
  end

  @doc """
  Returns the 4 edges of a face as `{vertex_a, vertex_b}` tuples.
  Edge i connects vertex i to vertex (i+1) mod 4.
  """
  def face_edges([v0, v1, v2, v3]) do
    [{v0, v1}, {v1, v2}, {v2, v3}, {v3, v0}]
  end

  @doc """
  For a given face and edge index (0-3), return the neighboring face
  and the edge index on that neighbor that is shared.
  """
  def neighbor(face_id, edge_index) do
    map = adjacency_map()
    neighbors = Map.get(map, face_id, [])
    Enum.at(neighbors, edge_index)
  end

  @doc """
  Returns the vertex order at a shared vertex.
  Examines how many faces meet at each vertex of the polyhedron.
  """
  def vertex_valence(vertex_index) do
    RT.vertex_orders() |> Map.get(vertex_index)
  end

  # Normalize an edge so the smaller vertex index comes first.
  defp normalize_edge({a, b}) when a <= b, do: {a, b}
  defp normalize_edge({a, b}), do: {b, a}
end
