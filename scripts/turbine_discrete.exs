# scripts/turbine_discrete.exs
#
# Simulates tick-by-tick turbine behavior with DISCRETE steam items.
#
# The reactor produces steam as whole items. A turbine either receives
# 1 steam item on a given tick or 0. This script simulates the actual
# speed oscillation and power output under burst/coast conditions.

defmodule DiscreteTurbine do
  @doc """
  Simulate one turbine for `duration` ticks.

  steam_schedule: list of tick numbers when a steam item arrives
  Returns: {avg_power, avg_speed, speed_history}
  """
  def simulate(steam_schedule, accel, friction, max_eff, peak, sigma, duration) do
    steam_set = MapSet.new(steam_schedule)

    {_final_speed, total_power, speeds} =
      Enum.reduce(0..(duration - 1), {0.0, 0.0, []}, fn tick, {speed, power_acc, speed_list} ->
        # Does this tick have steam?
        steam = if MapSet.member?(steam_set, tick), do: 1.0, else: 0.0

        # Accelerate then friction
        new_speed = (speed + steam * accel) * (1 - friction)

        # Power output this tick
        eff = max_eff * :math.exp(-:math.pow(new_speed - peak, 2) / (2 * sigma * sigma))
        power = eff * steam  # only produces power when consuming steam

        {new_speed, power_acc + power, [new_speed | speed_list]}
      end)

    avg_power = total_power / duration
    avg_speed = Enum.sum(speeds) / length(speeds)
    {avg_power, avg_speed, Enum.reverse(speeds)}
  end

  @doc "Generate evenly-spaced steam schedule: 1 item every `interval` ticks"
  def even_schedule(interval, duration) do
    Enum.take_while(
      Stream.iterate(0, &(&1 + interval)),
      &(&1 < duration)
    )
  end
end

IO.puts("=" |> String.duplicate(82))
IO.puts("  DISCRETE STEAM SIMULATION -- TICK-BY-TICK TURBINE BEHAVIOR")
IO.puts("=" |> String.duplicate(82))

peak = 1.5
base_max_eff = 480.0
base_sigma = 0.4
accel = 1.0
duration = 240

bearing_tiers = [
  {"No bearings (base)", 0.10, 1.0, 0.40},
  {"Bronze Bearings",    0.07, 1.5, 0.55},
  {"Steel Bearings",     0.05, 2.0, 0.75},
  {"Titanium Bearings",  0.03, 3.0, 1.00}
]

# Total steam from reactor over 240 ticks at 0.5/tick avg = 120 items
total_steam = 120

IO.puts("")
IO.puts("  Reactor produces #{total_steam} steam items over #{duration} ticks")
IO.puts("  (0.5 avg steam/tick = 1 item every 2 ticks)")
IO.puts("")

# For each bearing tier, simulate at optimal turbine count
IO.puts("== Discrete vs Continuous Comparison ==")
IO.puts("")

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult

  # What's the optimal turbine count from continuous model?
  {opt_n, _, cont_total} =
    Enum.reduce(1..30, {1, 0.0, 0.0}, fn n, {best_n, _best_pw, best_total} = acc ->
      steam_each = 0.5 / n
      speed = steam_each * accel * (1 - friction) / friction
      eff = max_eff * :math.exp(-:math.pow(speed - peak, 2) / (2 * sigma * sigma))
      pw = eff * steam_each
      total = pw * n
      if total > best_total, do: {n, pw, total}, else: acc
    end)

  IO.puts("  #{name} (friction=#{friction}, opt=#{opt_n} turbines):")

  # Steam per turbine over 240 ticks
  steam_per_turb = div(total_steam, opt_n)
  leftover = rem(total_steam, opt_n)

  # Interval between steam items for each turbine
  interval = if steam_per_turb > 0, do: div(duration, steam_per_turb), else: duration

  IO.puts("    Steam per turbine: #{steam_per_turb} items / #{duration} ticks = 1 every #{interval} ticks")
  if leftover > 0, do: IO.puts("    (#{leftover} leftover steam items not distributed)")

  # Simulate one turbine
  schedule = DiscreteTurbine.even_schedule(interval, duration)
  {avg_pw, avg_speed, speeds} = DiscreteTurbine.simulate(schedule, accel, friction, max_eff, peak, sigma, duration)
  discrete_total = avg_pw * opt_n

  # Speed range
  min_speed = Enum.min(speeds)
  max_speed = Enum.max(speeds)

  IO.puts("    Speed range: #{Float.round(min_speed, 3)} - #{Float.round(max_speed, 3)} (peak=#{peak})")
  IO.puts("    Avg speed:   #{Float.round(avg_speed, 3)}")
  IO.puts("    Continuous model: #{Float.round(cont_total, 0)}W")
  IO.puts("    Discrete model:   #{Float.round(discrete_total, 0)}W (#{Float.round(discrete_total / cont_total * 100, 0)}%)")

  # Show first 20 ticks of speed oscillation
  first_20 = Enum.take(speeds, 24)
  IO.puts("")
  IO.puts("    First 24 ticks (speed, * = steam tick):")

  Enum.with_index(first_20, fn speed, i ->
    has_steam = if i in schedule, do: "* ", else: "  "
    bar_width = round(speed / peak * 25)
    bar = String.duplicate("#", max(bar_width, 0))
    peak_marker = if bar_width >= 24 and bar_width <= 26, do: "|", else: ""

    IO.puts(
      "      t=#{String.pad_leading("#{i}", 3)} #{has_steam}" <>
      "spd=#{String.pad_leading("#{Float.round(speed, 3)}", 6)}  " <>
      bar <> peak_marker
    )
  end)

  IO.puts("")
end)

# -- The key question: does "power = eff * steam" make sense? --
IO.puts("== DESIGN QUESTION: When does the turbine produce power? ==")
IO.puts("")
IO.puts("  Option A: Power only on steam ticks (power = eff * steam)")
IO.puts("    - Turbine only generates when actively consuming steam")
IO.puts("    - Coast ticks produce nothing")
IO.puts("    - Feels like: steam is the fuel, speed is just efficiency modifier")
IO.puts("")
IO.puts("  Option B: Power every tick based on speed (power = f(speed))")
IO.puts("    - Turbine generates power whenever the rotor is spinning")
IO.puts("    - Steam adds energy, flywheel stores it, friction drains it")
IO.puts("    - Feels like: a real turbine with inertia")
IO.puts("")
IO.puts("  Let's compare both models:")
IO.puts("")

# Re-simulate with Option B: power every tick
Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult

  {opt_n, _, cont_total} =
    Enum.reduce(1..30, {1, 0.0, 0.0}, fn n, {best_n, _best_pw, best_total} = acc ->
      steam_each = 0.5 / n
      speed = steam_each * accel * (1 - friction) / friction
      eff = max_eff * :math.exp(-:math.pow(speed - peak, 2) / (2 * sigma * sigma))
      pw = eff * steam_each
      total = pw * n
      if total > best_total, do: {n, pw, total}, else: acc
    end)

  steam_per_turb = div(total_steam, opt_n)
  interval = if steam_per_turb > 0, do: div(duration, steam_per_turb), else: duration
  schedule = DiscreteTurbine.even_schedule(interval, duration)

  # Option A: power only on steam ticks (already computed above)
  steam_set = MapSet.new(schedule)
  {_, power_a, _} =
    Enum.reduce(0..(duration - 1), {0.0, 0.0, []}, fn tick, {speed, pw_acc, _} ->
      steam = if MapSet.member?(steam_set, tick), do: 1.0, else: 0.0
      new_speed = (speed + steam * accel) * (1 - friction)
      eff = max_eff * :math.exp(-:math.pow(new_speed - peak, 2) / (2 * sigma * sigma))
      power = eff * steam
      {new_speed, pw_acc + power, []}
    end)

  # Option B: power every tick based on speed
  # Power = base_power_rate * eff_fraction(speed)
  # We need to calibrate base_power_rate so continuous model matches
  # At peak speed, eff = max_eff, power should = 80W
  # If power = power_rate * (eff / max_eff), then power_rate = 80W
  power_rate = 80.0  # W at 100% efficiency
  {_, power_b, _} =
    Enum.reduce(0..(duration - 1), {0.0, 0.0, []}, fn tick, {speed, pw_acc, _} ->
      steam = if MapSet.member?(steam_set, tick), do: 1.0, else: 0.0
      new_speed = (speed + steam * accel) * (1 - friction)
      eff_frac = :math.exp(-:math.pow(new_speed - peak, 2) / (2 * sigma * sigma))
      power = power_rate * eff_mult * eff_frac
      {new_speed, pw_acc + power, []}
    end)

  total_a = power_a / duration * opt_n
  total_b = power_b / duration * opt_n

  IO.puts(
    "  #{String.pad_trailing(name, 22)} " <>
    "#{opt_n} turbs: " <>
    "A=#{String.pad_leading("#{Float.round(total_a, 0)}", 5)}W  " <>
    "B=#{String.pad_leading("#{Float.round(total_b, 0)}", 5)}W  " <>
    "cont=#{String.pad_leading("#{Float.round(cont_total, 0)}", 5)}W"
  )
end)
