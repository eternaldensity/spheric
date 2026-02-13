defmodule Spheric.Geometry.TileNeighbors do
  @moduledoc """
  Tile-level neighbor resolution for the subdivided spherical grid.

  Given a tile `{face, row, col}` and a direction (0-3), returns the
  neighboring tile address, which may be on an adjacent face.

  Direction mapping (in face-local grid coordinates):
    0 -> col+1 (along e1, "right")
    1 -> row+1 (along e2, "down")
    2 -> col-1 (along -e1, "left")
    3 -> row-1 (along -e2, "up")

  Face grid layout:
    origin = v0, e1 = v1-v0 (col axis), e2 = v3-v0 (row axis)
    Edge 0: v0->v1 (row=0, col varies)
    Edge 1: v1->v2 (col=max, row varies)
    Edge 2: v2->v3 (row=max, col varies reversed)
    Edge 3: v3->v0 (col=0, row varies reversed)
  """

  alias Spheric.Geometry.Adjacency
  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @adjacency Adjacency.adjacency_map()
  @faces RT.faces()

  @type direction :: 0 | 1 | 2 | 3
  @type tile_address :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  Returns the neighbor tile in the given direction.

  Returns `{:ok, {face, row, col}}` or `:boundary` if no valid neighbor exists.
  """
  def neighbor(tile, direction),
    do: neighbor(tile, direction, Application.get_env(:spheric, :subdivisions, 64))

  # Direction 0: col + 1 (interior)
  def neighbor({face, row, col}, 0, n) when col + 1 < n do
    {:ok, {face, row, col + 1}}
  end

  # Direction 1: row + 1 (interior)
  def neighbor({face, row, col}, 1, n) when row + 1 < n do
    {:ok, {face, row + 1, col}}
  end

  # Direction 2: col - 1 (interior)
  def neighbor({face, row, col}, 2, _n) when col > 0 do
    {:ok, {face, row, col - 1}}
  end

  # Direction 3: row - 1 (interior)
  def neighbor({face, row, col}, 3, _n) when row > 0 do
    {:ok, {face, row - 1, col}}
  end

  # Cross-face cases
  def neighbor({face, row, col}, direction, n) do
    cross_face_neighbor(face, row, col, direction, n)
  end

  defp cross_face_neighbor(face, row, col, direction, n) do
    max = n - 1

    # Determine which face edge we're crossing and our position along it
    {my_edge, pos_along_edge} = direction_to_edge(direction, row, col, max)

    # Look up the neighbor face and their shared edge
    neighbors = Map.get(@adjacency, face)
    neighbor_info = Enum.at(neighbors, my_edge)

    case neighbor_info do
      nil ->
        :boundary

      %{face: neighbor_face, their_edge: their_edge, shared_vertices: my_shared} ->
        # Determine if vertex order is flipped between the two faces
        flipped? = edge_flipped?(face, my_edge, neighbor_face, their_edge, my_shared)

        pos = if flipped?, do: max - pos_along_edge, else: pos_along_edge

        {new_row, new_col} = remap_to_neighbor(their_edge, pos, max)
        {:ok, {neighbor_face, new_row, new_col}}
    end
  end

  # Maps grid direction to face edge index and position along that edge
  # Direction 0 (col+1 overflow) -> crossing edge 1 (v1->v2)
  # Position along edge 1: row=0 is near v1, row=max is near v2
  defp direction_to_edge(0, row, _col, _max), do: {1, row}

  # Direction 1 (row+1 overflow) -> crossing edge 2 (v2->v3)
  # Position along edge 2: col=max is near v2, col=0 is near v3
  defp direction_to_edge(1, _row, col, max), do: {2, max - col}

  # Direction 2 (col-1 underflow) -> crossing edge 3 (v3->v0)
  # Position along edge 3: row=max is near v3, row=0 is near v0
  defp direction_to_edge(2, row, _col, max), do: {3, max - row}

  # Direction 3 (row-1 underflow) -> crossing edge 0 (v0->v1)
  # Position along edge 0: col=0 is near v0, col=max is near v1
  defp direction_to_edge(3, _row, col, _max), do: {0, col}

  # Check if the shared edge vertices are traversed in opposite order
  # by the two faces. If so, position along the edge needs to be flipped.
  defp edge_flipped?(my_face, my_edge, neighbor_face, their_edge, _my_shared) do
    my_verts = get_edge_vertices(my_face, my_edge)
    their_verts = get_edge_vertices(neighbor_face, their_edge)

    # Two faces share the same edge. If they traverse the shared vertices
    # in the same order, no flip. If reversed, flip.
    # Since faces have outward-facing CCW winding and they share an edge,
    # the edge is traversed in opposite directions by the two faces.
    # However, we need to compare the actual vertex indices.
    {my_a, my_b} = my_verts
    {their_a, their_b} = their_verts

    # Same order means my_a == their_a and my_b == their_b
    # Reversed means my_a == their_b and my_b == their_a
    cond do
      my_a == their_a and my_b == their_b -> false
      my_a == their_b and my_b == their_a -> true
      true -> false
    end
  end

  # Get the two vertex indices for a given face edge
  defp get_edge_vertices(face_id, edge_index) do
    [v0, v1, v2, v3] = Enum.at(@faces, face_id)

    case edge_index do
      0 -> {v0, v1}
      1 -> {v1, v2}
      2 -> {v2, v3}
      3 -> {v3, v0}
    end
  end

  # Remaps a position along the neighbor's edge into their (row, col) system
  # pos is the position along the neighbor's edge (0..max)
  defp remap_to_neighbor(their_edge, pos, max) do
    case their_edge do
      # Entering via neighbor's edge 0 (v0->v1, row=0 boundary)
      # We arrive at row=0, position along edge -> col
      0 -> {0, pos}
      # Entering via neighbor's edge 1 (v1->v2, col=max boundary)
      # We arrive at col=max, position along edge -> row
      1 -> {pos, max}
      # Entering via neighbor's edge 2 (v2->v3, row=max boundary)
      # We arrive at row=max, position along edge -> col (reversed)
      2 -> {max, max - pos}
      # Entering via neighbor's edge 3 (v3->v0, col=0 boundary)
      # We arrive at col=0, position along edge -> row (reversed)
      3 -> {max - pos, 0}
    end
  end
end
