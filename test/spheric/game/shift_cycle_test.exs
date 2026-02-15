defmodule Spheric.Game.ShiftCycleTest do
  use ExUnit.Case, async: false

  alias Spheric.Game.ShiftCycle

  setup do
    ShiftCycle.init()
    ShiftCycle.clear()
    ShiftCycle.init()

    on_exit(fn ->
      ShiftCycle.clear()
    end)

    :ok
  end

  describe "init/0" do
    test "initializes with dawn phase" do
      state = ShiftCycle.state()
      assert state.current_phase == :dawn
      assert state.sun_angle == 0.0
      assert state.phase_tick == 0
    end

    test "does not overwrite existing state on re-init" do
      ShiftCycle.put_state(%{sun_angle: 1.5, current_phase: :zenith, phase_tick: 100})
      ShiftCycle.init()

      state = ShiftCycle.state()
      assert state.current_phase == :zenith
    end
  end

  describe "current_phase/0" do
    test "returns dawn initially" do
      assert ShiftCycle.current_phase() == :dawn
    end

    test "returns correct phase after state change" do
      ShiftCycle.put_state(%{sun_angle: :math.pi() / 2, current_phase: :zenith, phase_tick: 0})
      assert ShiftCycle.current_phase() == :zenith
    end
  end

  describe "phases/0" do
    test "returns all four phases" do
      assert ShiftCycle.phases() == [:dawn, :zenith, :dusk, :nadir]
    end
  end

  describe "phase_duration/0" do
    test "returns 600" do
      assert ShiftCycle.phase_duration() == 600
    end
  end

  describe "current_modifiers/0" do
    test "returns modifiers for dawn phase" do
      mods = ShiftCycle.current_modifiers()
      assert mods.tundra == 0.20
      assert mods.volcanic == -0.10
      assert mods.grassland == 0.0
    end

    test "returns modifiers for zenith phase" do
      ShiftCycle.put_state(%{sun_angle: :math.pi() / 2, current_phase: :zenith, phase_tick: 0})
      mods = ShiftCycle.current_modifiers()
      assert mods.desert == 0.20
      assert mods.forest == -0.10
    end
  end

  describe "biome_modifier/1" do
    test "returns correct modifier for tundra in dawn" do
      assert ShiftCycle.biome_modifier(:tundra) == 0.20
    end

    test "returns 0.0 for unaffected biome" do
      assert ShiftCycle.biome_modifier(:grassland) == 0.0
    end

    test "returns 0.0 for unknown biome" do
      assert ShiftCycle.biome_modifier(:unknown_biome) == 0.0
    end
  end

  describe "current_lighting/0" do
    test "returns lighting for dawn" do
      lighting = ShiftCycle.current_lighting()
      assert Map.has_key?(lighting, :ambient)
      assert Map.has_key?(lighting, :directional)
      assert Map.has_key?(lighting, :intensity)
      assert Map.has_key?(lighting, :bg)
      assert lighting.intensity == 0.7
    end
  end

  describe "sun_direction/0" do
    test "returns {1.0, 0.0, 0.0} at angle 0" do
      {x, y, z} = ShiftCycle.sun_direction()
      assert_in_delta x, 1.0, 0.001
      assert_in_delta y, 0.0, 0.001
      assert_in_delta z, 0.0, 0.001
    end

    test "rotates with sun angle" do
      ShiftCycle.put_state(%{sun_angle: :math.pi() / 2, current_phase: :zenith, phase_tick: 0})
      {x, _y, z} = ShiftCycle.sun_direction()
      assert_in_delta x, 0.0, 0.001
      assert_in_delta z, 1.0, 0.001
    end
  end

  describe "face_illumination/1" do
    test "returns value between 0.0 and 1.0" do
      for face_id <- 0..29 do
        illum = ShiftCycle.face_illumination(face_id)
        assert illum >= 0.0
        assert illum <= 1.0
      end
    end
  end

  describe "dark?/1" do
    test "correctly identifies dark faces" do
      # At angle 0, sun points in +X direction
      # Some faces should be dark (facing away from sun)
      dark_count = Enum.count(0..29, &ShiftCycle.dark?/1)
      light_count = 30 - dark_count
      # At least some faces should be lit and some dark
      assert light_count > 0
      assert dark_count > 0
    end
  end

  describe "face_normal/1" do
    test "returns a 3-tuple for each face" do
      for face_id <- 0..29 do
        {x, y, z} = ShiftCycle.face_normal(face_id)
        assert is_float(x)
        assert is_float(y)
        assert is_float(z)
      end
    end

    test "normals are normalized (unit length)" do
      for face_id <- 0..29 do
        {x, y, z} = ShiftCycle.face_normal(face_id)
        length = :math.sqrt(x * x + y * y + z * z)
        assert_in_delta length, 1.0, 0.001
      end
    end
  end

  describe "apply_rate_modifier/2" do
    test "reduces rate for positive modifier (dawn + tundra)" do
      # Dawn phase, tundra has +0.20 modifier
      result = ShiftCycle.apply_rate_modifier(10, :tundra)
      # 10 * (1.0 - 0.20) = 8
      assert result == 8
    end

    test "increases rate for negative modifier (dawn + volcanic)" do
      # Dawn phase, volcanic has -0.10 modifier
      result = ShiftCycle.apply_rate_modifier(10, :volcanic)
      # 10 * (1.0 - (-0.10)) = 11
      assert result == 11
    end

    test "returns base rate for neutral biome" do
      result = ShiftCycle.apply_rate_modifier(10, :grassland)
      assert result == 10
    end

    test "never goes below 1" do
      result = ShiftCycle.apply_rate_modifier(1, :tundra)
      assert result >= 1
    end
  end

  describe "process_tick/1" do
    test "returns :no_change on non-10th ticks" do
      assert ShiftCycle.process_tick(1) == :no_change
      assert ShiftCycle.process_tick(7) == :no_change
    end

    test "advances sun and returns :sun_moved on 10th ticks" do
      result = ShiftCycle.process_tick(10)
      assert {:sun_moved, {_x, _y, _z}} = result
    end

    test "returns phase_changed when phase transitions" do
      # Advance to near end of dawn phase
      # Dawn is angle 0 to pi/2, with full cycle of 2400 ticks
      # Each step advances by 2*pi*10/2400 = pi/120
      # To cross pi/2 we need 60 steps = 600 ticks
      state = %{
        sun_angle: :math.pi() / 2 - 0.01,
        current_phase: :dawn,
        phase_tick: 590
      }
      ShiftCycle.put_state(state)

      result = ShiftCycle.process_tick(600)
      assert {:phase_changed, :zenith, _lighting, _modifiers, _sun_dir} = result
    end
  end

  describe "put_state/1" do
    test "stores state correctly" do
      ShiftCycle.put_state(%{sun_angle: 2.0, current_phase: :dusk, phase_tick: 50})
      state = ShiftCycle.state()
      assert state.sun_angle == 2.0
      assert state.current_phase == :dusk
    end

    test "migrates old state without sun_angle" do
      ShiftCycle.put_state(%{current_phase: :nadir, phase_tick: 100})
      state = ShiftCycle.state()
      assert state.sun_angle == 0.0
    end
  end

  describe "phase_progress/0" do
    test "returns 0 initially" do
      assert ShiftCycle.phase_progress() == 0
    end

    test "returns percentage through phase" do
      ShiftCycle.put_state(%{sun_angle: 0.0, current_phase: :dawn, phase_tick: 300})
      assert ShiftCycle.phase_progress() == 50
    end
  end

  describe "phase_info/1" do
    test "returns info for known phases" do
      assert ShiftCycle.phase_info(:dawn).name == "Dawn Shift"
      assert ShiftCycle.phase_info(:zenith).name == "Zenith Shift"
      assert ShiftCycle.phase_info(:dusk).name == "Dusk Shift"
      assert ShiftCycle.phase_info(:nadir).name == "Nadir Shift"
    end

    test "returns unknown for invalid phase" do
      assert ShiftCycle.phase_info(:invalid).name == "Unknown"
    end
  end

  describe "lighting_for_camera/1" do
    test "returns lighting data with phase for a camera direction" do
      result = ShiftCycle.lighting_for_camera({1.0, 0.0, 0.0})
      assert Map.has_key?(result, :phase)
      assert Map.has_key?(result, :ambient)
      assert Map.has_key?(result, :directional)
      assert Map.has_key?(result, :intensity)
      assert Map.has_key?(result, :bg)
    end

    test "handles zero-length camera direction" do
      result = ShiftCycle.lighting_for_camera({0.0, 0.0, 0.0})
      assert Map.has_key?(result, :phase)
    end

    test "facing sun gives brighter lighting than facing away" do
      sun_dir = ShiftCycle.sun_direction()
      {sx, sy, sz} = sun_dir

      toward_sun = ShiftCycle.lighting_for_camera({sx, sy, sz})
      away_from_sun = ShiftCycle.lighting_for_camera({-sx, -sy, -sz})

      assert toward_sun.intensity >= away_from_sun.intensity
    end
  end
end
