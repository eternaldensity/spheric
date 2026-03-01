# scripts/turbine_sim.exs
#
# Simulates variable-speed steam turbine with BELL CURVE (Gaussian) efficiency.
#
# Design:
#   - Base reactor with 3 turbines outputs 240W (3 x 80W)
#   - Nuclear cell lasts 240 ticks (4 phases of 60 ticks)
#   - 3 turbines is optimal at base friction (0.10)
#   - Bearing upgrades increase max_eff AND widen sigma
#   - This shifts optimal turbine count upward AND increases total output

defmodule TurbineSim do
  def terminal_speed(steam_per_tick, accel, friction) do
    steam_per_tick * accel * (1 - friction) / friction
  end

  def efficiency(speed, max_eff, peak, sigma) do
    max_eff * :math.exp(-:math.pow(speed - peak, 2) / (2 * sigma * sigma))
  end

  def total_output(avg_steam, n_turbines, accel, friction, max_eff, peak, sigma) do
    steam_each = avg_steam / n_turbines
    speed = terminal_speed(steam_each, accel, friction)
    eff = efficiency(speed, max_eff, peak, sigma)
    power_each = eff * steam_each
    {power_each, power_each * n_turbines, speed, eff}
  end

  def find_optimal(avg_steam, accel, friction, max_eff, peak, sigma, range \\ 1..30) do
    Enum.reduce(range, {1, 0.0, 0.0}, fn n, {best_n, _best_pw, best_total} = acc ->
      {pw, total, _, _} = total_output(avg_steam, n, accel, friction, max_eff, peak, sigma)
      if total > best_total, do: {n, pw, total}, else: acc
    end)
  end
end

IO.puts("=" |> String.duplicate(82))
IO.puts("  VARIABLE-SPEED STEAM TURBINE -- 3 BASE TURBINES, 240-TICK CELLS")
IO.puts("=" |> String.duplicate(82))

# -- Reactor parameters --
avg_steam = 0.5
accel = 1.0
base_friction = 0.10
cell_duration = 240  # ticks per nuclear cell (was 120)

# -- Calibration --
# Base terminal speed with 3 turbines:
#   steam_each = 0.5/3 = 0.1667
#   terminal = 0.1667 * 1.0 * 0.9 / 0.1 = 1.5
#
# We want 80W per turbine at peak speed.
# power = eff(peak) * steam_each = max_eff * 0.1667
# 80 = max_eff * 0.1667
# max_eff = 480 W/steam

peak = 1.5
base_max_eff = 480.0
base_sigma = 0.4

# Bearing tiers: {name, friction, max_eff_multiplier, sigma}
bearing_tiers = [
  {"No bearings (base)", 0.10, 1.0, 0.40},
  {"Bronze Bearings",    0.07, 1.5, 0.55},
  {"Steel Bearings",     0.05, 2.0, 0.75},
  {"Titanium Bearings",  0.03, 3.0, 1.00}
]

IO.puts("")
IO.puts("  Peak speed     = #{peak} (base terminal speed with 3 turbines)")
IO.puts("  Base max_eff   = #{base_max_eff} W/steam")
IO.puts("  Base sigma     = #{base_sigma}")
IO.puts("  Cell duration  = #{cell_duration} ticks (was 120)")
IO.puts("  Avg steam      = #{avg_steam}/tick")
IO.puts("  Base target    = 3 turbs x 80W = 240W")
IO.puts("")

# -- Show bearing parameters --
IO.puts("== Bearing Parameters ==")
IO.puts("")
IO.puts(
  String.pad_trailing("Bearing Tier", 24) <>
  String.pad_leading("Friction", 10) <>
  String.pad_leading("Max Eff", 10) <>
  String.pad_leading("Sigma", 8) <>
  String.pad_leading("Term @3", 10) <>
  String.pad_leading("Eff% @3", 10)
)
IO.puts(String.duplicate("-", 72))

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult
  speed_at_3 = TurbineSim.terminal_speed(avg_steam / 3, accel, friction)
  eff_at_3 = TurbineSim.efficiency(speed_at_3, max_eff, peak, sigma)
  eff_pct = eff_at_3 / max_eff * 100

  IO.puts(
    String.pad_trailing(name, 24) <>
    String.pad_leading("#{friction}", 10) <>
    String.pad_leading("#{Float.round(max_eff, 0)}", 10) <>
    String.pad_leading("#{sigma}", 8) <>
    String.pad_leading("#{Float.round(speed_at_3, 3)}", 10) <>
    String.pad_leading("#{Float.round(eff_pct, 1)}%", 10)
  )
end)

IO.puts("")

# -- Main comparison --
# Nuclear cell cost stays the same, but duration doubles -> 2x thermal items
cell_cost = 43_271.2
thermal_per_phase = (1_184.8 + 1_323.5) / 2  # cost of 1 thermal regulator + 1 coolant rod
# 240 ticks = 4 phases (was 2 phases at 120 ticks)
n_phases = cell_duration / 60
thermal_per_cell = thermal_per_phase * n_phases

IO.puts("== Cost Calculation ==")
IO.puts("  Nuclear cell cost:  #{Float.round(cell_cost, 1)} Wt")
IO.puts("  Phases per cell:    #{n_phases} (#{cell_duration}/60)")
IO.puts("  Thermal cost/phase: #{Float.round(thermal_per_phase, 1)} Wt")
IO.puts("  Total thermal/cell: #{Float.round(thermal_per_cell, 1)} Wt")
IO.puts("  Total cost/cell:    #{Float.round(cell_cost + thermal_per_cell, 1)} Wt")
IO.puts("")

IO.puts("== Bearing Tier Progression ==")
IO.puts("")
IO.puts(
  String.pad_trailing("Bearing Tier", 24) <>
  String.pad_leading("Opt #turb", 10) <>
  String.pad_leading("W/turb", 10) <>
  String.pad_leading("Total W", 10) <>
  String.pad_leading("vs Base", 10) <>
  String.pad_leading("Gross Wt", 10) <>
  String.pad_leading("ROI", 10)
)
IO.puts(String.duplicate("-", 84))

base_total_ref = 240.0  # 3 turbines x 80W

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult

  {opt_n, opt_pw, opt_total} =
    TurbineSim.find_optimal(avg_steam, accel, friction, max_eff, peak, sigma)

  vs_base = opt_total / base_total_ref * 100
  gross = opt_total * cell_duration
  cost = cell_cost + thermal_per_cell
  roi = gross / cost

  IO.puts(
    String.pad_trailing(name, 24) <>
    String.pad_leading("#{opt_n}", 10) <>
    String.pad_leading("#{Float.round(opt_pw, 1)}W", 10) <>
    String.pad_leading("#{Float.round(opt_total, 0)}W", 10) <>
    String.pad_leading("#{Float.round(vs_base, 0)}%", 10) <>
    String.pad_leading("#{Float.round(gross, 0)}", 10) <>
    String.pad_leading("#{Float.round(roi, 2)}x", 10)
  )
end)

bio_roi = 240.0 * cell_duration / 3_256.1
IO.puts(
  String.pad_trailing("12 Bio Gens (stable)", 24) <>
  String.pad_leading("12", 10) <>
  String.pad_leading("20.0W", 10) <>
  String.pad_leading("240W", 10) <>
  String.pad_leading("100%", 10) <>
  String.pad_leading("#{Float.round(240.0 * cell_duration, 0)}", 10) <>
  String.pad_leading("#{Float.round(bio_roi, 2)}x", 10)
)

IO.puts("")

# -- Turbine count sweep per bearing tier --
IO.puts("== Turbine count sweep per bearing tier ==")
IO.puts("")

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult
  IO.puts("  #{name} (friction=#{friction}, sigma=#{sigma}, max_eff=#{Float.round(max_eff, 0)}):")

  {_, _, opt_total} =
    TurbineSim.find_optimal(avg_steam, accel, friction, max_eff, peak, sigma)

  Enum.each(1..15, fn n ->
    {pw, total, speed, eff} =
      TurbineSim.total_output(avg_steam, n, accel, friction, max_eff, peak, sigma)
    eff_pct = eff / max_eff * 100
    pct_of_opt = if opt_total > 0, do: total / opt_total * 100, else: 0
    bar_len = round(pct_of_opt / 3)
    bar = String.duplicate("#", max(bar_len, 0))
    optimal = if abs(total - opt_total) < 0.5, do: " <-- optimal", else: ""

    speed_label = cond do
      speed > peak * 1.05 -> "OVER"
      speed < peak * 0.95 -> "under"
      true -> "=PEAK"
    end

    IO.puts(
      "    #{String.pad_leading("#{n}", 2)} turbs: " <>
      "#{String.pad_leading("#{Float.round(total, 0)}", 5)}W total, " <>
      "#{String.pad_leading("#{Float.round(pw, 1)}", 6)}W/ea, " <>
      "spd=#{String.pad_leading("#{Float.round(speed, 2)}", 5)} " <>
      "(#{String.pad_trailing(speed_label, 5)}) " <>
      "eff=#{String.pad_leading("#{Float.round(eff_pct, 0)}", 3)}%  " <>
      bar <> optimal
    )
  end)

  IO.puts("")
end)

# -- What happens keeping 3 turbines with bearing upgrades? --
IO.puts("== 3 turbines at each bearing tier (no turbine count change) ==")
IO.puts("")

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult
  {pw, total, speed, eff} =
    TurbineSim.total_output(avg_steam, 3, accel, friction, max_eff, peak, sigma)
  eff_pct = eff / max_eff * 100

  {opt_n, _, opt_total} =
    TurbineSim.find_optimal(avg_steam, accel, friction, max_eff, peak, sigma)

  wasted = if opt_total > 0, do: (1 - total / opt_total) * 100, else: 0

  IO.puts(
    "  #{String.pad_trailing(name, 22)} " <>
    "speed=#{String.pad_leading("#{Float.round(speed, 2)}", 5)}, " <>
    "eff=#{String.pad_leading("#{Float.round(eff_pct, 0)}", 3)}%, " <>
    "total=#{String.pad_leading("#{Float.round(total, 0)}", 4)}W " <>
    "(optimal: #{opt_n} turbs = #{Float.round(opt_total, 0)}W, " <>
    "wasting #{Float.round(wasted, 0)}%)"
  )
end)

IO.puts("")
IO.puts("== SUMMARY ==")
IO.puts("")
IO.puts("  Nuclear cell: 240 ticks (4 phases), same production cost")
IO.puts("  Base: 3 turbines x 80W = 240W")
IO.puts("  Bearings increase max_eff (1x -> 1.5x -> 2x -> 3x) AND widen sigma")
IO.puts("")
IO.puts("  Upgrade path requires BOTH better bearings AND more turbines.")
IO.puts("  Upgrading bearings without adding turbines overspeeds existing turbines.")
