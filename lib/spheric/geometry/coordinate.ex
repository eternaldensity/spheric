defmodule Spheric.Geometry.Coordinate do
  @moduledoc """
  Tile coordinate system for the spherical grid.

  Each tile is addressed as `{face_id, row, col}` where face_id is 0-29
  and row/col are 0-based within the face's subdivision grid.
  """

  alias Spheric.Geometry.RhombicTriacontahedron, as: RT

  @type tile_address :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  Returns face IDs visible from a camera position, sorted by proximity.

  A face is visible if its center (normalized to the sphere surface)
  has a positive dot product with the camera direction. This gives
  roughly the hemisphere facing the camera.
  """
  def visible_faces({cx, cy, cz}) do
    cam_len = :math.sqrt(cx * cx + cy * cy + cz * cz)

    if cam_len < 1.0e-10 do
      Enum.to_list(0..29)
    else
      cam_dir = {cx / cam_len, cy / cam_len, cz / cam_len}

      RT.face_centers()
      |> Enum.with_index()
      |> Enum.map(fn {center, face_id} ->
        norm_center = RT.normalize(center)
        dot = dot3(norm_center, cam_dir)
        {face_id, dot}
      end)
      |> Enum.filter(fn {_face_id, dot} -> dot > -0.3 end)
      |> Enum.sort_by(fn {_face_id, dot} -> -dot end)
      |> Enum.map(fn {face_id, _dot} -> face_id end)
    end
  end

  defp dot3({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz
end
