defmodule Spheric.Geometry.RhombicTriacontahedron do
  @moduledoc """
  Defines the rhombic triacontahedron: 32 vertices, 30 golden-rhombus faces, 60 edges.

  Vertices are classified by valence:
  - 12 order-5 vertices (V0–V11) — dodecahedron vertices, at obtuse rhombus corners
  - 20 order-3 vertices (V12–V31) — icosahedron vertices, at acute rhombus corners

  Coordinates from dmccooey.com, using golden ratio constants:
    C0 = sqrt(5)/4, C1 = (5+sqrt(5))/8, C2 = (5+3*sqrt(5))/8
  Note: C2 = C0 + C1.

  Face vertex winding is counter-clockwise when viewed from outside (outward normals).
  Vertices alternate [order-5, order-3, order-5, order-3] around each face.
  """

  @c0 :math.sqrt(5) / 4
  @c1 (5 + :math.sqrt(5)) / 8
  @c2 (5 + 3 * :math.sqrt(5)) / 8

  @doc "Returns the 32 vertices as a list of `{x, y, z}` tuples."
  def vertices do
    [
      # 12 order-5 vertices (dodecahedron positions)
      {@c1, 0.0, @c2},
      {@c1, 0.0, -@c2},
      {-@c1, 0.0, @c2},
      {-@c1, 0.0, -@c2},
      {@c2, @c1, 0.0},
      {@c2, -@c1, 0.0},
      {-@c2, @c1, 0.0},
      {-@c2, -@c1, 0.0},
      {0.0, @c2, @c1},
      {0.0, @c2, -@c1},
      {0.0, -@c2, @c1},
      {0.0, -@c2, -@c1},
      # 20 order-3 vertices (icosahedron positions)
      {0.0, @c0, @c2},
      {0.0, @c0, -@c2},
      {0.0, -@c0, @c2},
      {0.0, -@c0, -@c2},
      {@c2, 0.0, @c0},
      {@c2, 0.0, -@c0},
      {-@c2, 0.0, @c0},
      {-@c2, 0.0, -@c0},
      {@c0, @c2, 0.0},
      {@c0, -@c2, 0.0},
      {-@c0, @c2, 0.0},
      {-@c0, -@c2, 0.0},
      {@c1, @c1, @c1},
      {@c1, @c1, -@c1},
      {@c1, -@c1, @c1},
      {@c1, -@c1, -@c1},
      {-@c1, @c1, @c1},
      {-@c1, @c1, -@c1},
      {-@c1, -@c1, @c1},
      {-@c1, -@c1, -@c1}
    ]
  end

  @doc """
  Returns the 30 faces as lists of 4 vertex indices.

  Each face is `[a, b, c, d]` in CCW winding order (viewed from outside).
  Vertices alternate: a=order-5, b=order-3, c=order-5, d=order-3.
  The long diagonal (connecting the two order-5 vertices) is a–c.
  The short diagonal (connecting the two order-3 vertices) is b–d.
  """
  def faces do
    [
      [0, 12, 2, 14],
      [0, 14, 10, 26],
      [0, 26, 5, 16],
      [1, 13, 9, 25],
      [1, 25, 4, 17],
      [1, 17, 5, 27],
      [2, 28, 6, 18],
      [2, 18, 7, 30],
      [2, 30, 10, 14],
      [3, 19, 6, 29],
      [3, 29, 9, 13],
      [3, 13, 1, 15],
      [4, 20, 8, 24],
      [4, 24, 0, 16],
      [4, 16, 5, 17],
      [7, 18, 6, 19],
      [7, 19, 3, 31],
      [7, 31, 11, 23],
      [8, 22, 6, 28],
      [8, 28, 2, 12],
      [8, 12, 0, 24],
      [9, 29, 6, 22],
      [9, 22, 8, 20],
      [9, 20, 4, 25],
      [10, 30, 7, 23],
      [10, 23, 11, 21],
      [10, 21, 5, 26],
      [11, 31, 3, 15],
      [11, 15, 1, 27],
      [11, 27, 5, 21]
    ]
  end

  @doc "Returns the number of faces meeting at each vertex (3 or 5)."
  def vertex_orders do
    faces()
    |> Enum.with_index()
    |> Enum.flat_map(fn {face_verts, _face_id} -> face_verts end)
    |> Enum.frequencies()
  end

  @doc "Returns the list of order-5 vertex indices (0–11)."
  def order5_vertices, do: Enum.to_list(0..11)

  @doc "Returns the list of order-3 vertex indices (12–31)."
  def order3_vertices, do: Enum.to_list(12..31)

  @doc "Returns the face center (average of 4 corner positions), NOT normalized."
  def face_center(face_index) do
    verts = vertices()
    [a, b, c, d] = Enum.at(faces(), face_index)

    {ax, ay, az} = Enum.at(verts, a)
    {bx, by, bz} = Enum.at(verts, b)
    {cx, cy, cz} = Enum.at(verts, c)
    {dx, dy, dz} = Enum.at(verts, d)

    {(ax + bx + cx + dx) / 4, (ay + by + cy + dy) / 4, (az + bz + cz + dz) / 4}
  end

  @doc "Returns all 30 face centers."
  def face_centers do
    Enum.map(0..29, &face_center/1)
  end

  @doc "Normalize a 3D point to lie on a sphere of given radius."
  def normalize({x, y, z}, radius \\ 1.0) do
    len = :math.sqrt(x * x + y * y + z * z)
    {x / len * radius, y / len * radius, z / len * radius}
  end

  @doc """
  Returns a JSON-friendly payload for the client.

  Contains the 32 vertices as a flat list `[x0,y0,z0, x1,y1,z1, ...]`
  and the 30 faces as a list of 4-element lists.
  """
  def client_payload do
    flat_vertices =
      vertices()
      |> Enum.flat_map(fn {x, y, z} -> [x, y, z] end)

    %{
      vertices: flat_vertices,
      faces: faces(),
      subdivisions: Application.get_env(:spheric, :subdivisions, 64),
      cells_per_axis: 4
    }
  end
end
