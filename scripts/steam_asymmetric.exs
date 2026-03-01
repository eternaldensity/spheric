# scripts/steam_asymmetric.exs
#
# What if the reactor runs at different temperature ranges?
# Explores asymmetric heating patterns and their effect on power output.
#
# Scenarios:
#   1. Standard: 100↔200 (avg 150, avg steam 0.5)
#   2. High: 150↔250 (avg 200, avg steam 1.0) — if we move danger up
#   3. Asymmetric: 2 heat + 1 cool (100→200→300→200, avg ~200)
#   4. Player-controlled setpoint: what if danger temp is configurable?

defmodule AsymSim do
  # Reuse the fixed-demand model from steam_pressure.exs

  defstruct [
    :pressure, :capacity,
    :temperature, :operating_temp,
    :phase_schedule,  # list of {:heat | :cool, duration_ticks}
    :phase_index, :phase_tick,
    :temp_rate,
    :turbine_speeds, :accel, :friction,
    :max_eff, :peak_speed, :sigma,
    :demand_per_turbine,
    :total_power, :total_steam_produced, :total_steam_consumed,
    :total_steam_vented, :total_ticks_starved, :tick_count,
    :speed_histories, :temp_history, :pressure_history,
    :peak_temp, :min_temp  # track extremes
  ]

  def init(opts) do
    n = Keyword.fetch!(opts, :turbines)
    %AsymSim{
      pressure: 0.0,
      capacity: Keyword.get(opts, :capacity, 2.0),
      temperature: Keyword.get(opts, :start_temp, 100.0),
      operating_temp: Keyword.get(opts, :operating_temp, 100.0),
      phase_schedule: Keyword.fetch!(opts, :schedule),
      phase_index: 0,
      phase_tick: 0,
      temp_rate: Keyword.get(opts, :temp_rate, 1.667),
      turbine_speeds: List.duplicate(0.0, n),
      accel: Keyword.get(opts, :accel, 1.0),
      friction: Keyword.fetch!(opts, :friction),
      max_eff: Keyword.fetch!(opts, :max_eff),
      peak_speed: Keyword.get(opts, :peak_speed, 1.5),
      sigma: Keyword.fetch!(opts, :sigma),
      demand_per_turbine: Keyword.fetch!(opts, :demand),
      total_power: 0.0, total_steam_produced: 0.0,
      total_steam_consumed: 0.0, total_steam_vented: 0.0,
      total_ticks_starved: 0, tick_count: 0,
      speed_histories: List.duplicate([], n),
      temp_history: [], pressure_history: [],
      peak_temp: 0.0, min_temp: 999.0
    }
  end

  def simulate(st, duration) do
    Enum.reduce(1..duration, st, fn _, s ->
      s |> step_reactor() |> step_turbines() |> record()
    end)
  end

  def step_reactor(st) do
    schedule = st.phase_schedule
    {direction, phase_len} = Enum.at(schedule, rem(st.phase_index, length(schedule)))

    delta = case direction do
      :heat -> st.temp_rate
      :cool -> -st.temp_rate
    end

    new_temp = max(st.temperature + delta, 0.0)

    # Phase boundary
    {new_idx, new_pt} =
      if st.phase_tick >= phase_len - 1,
        do: {st.phase_index + 1, 0},
        else: {st.phase_index, st.phase_tick + 1}

    # Steam production
    steam = if new_temp > st.operating_temp,
      do: (new_temp - st.operating_temp) / 100.0, else: 0.0

    new_p = st.pressure + steam
    vented = max(new_p - st.capacity, 0.0)

    %{st |
      temperature: new_temp,
      phase_index: new_idx,
      phase_tick: new_pt,
      pressure: min(new_p, st.capacity),
      total_steam_produced: st.total_steam_produced + steam,
      total_steam_vented: st.total_steam_vented + vented,
      peak_temp: max(st.peak_temp, new_temp),
      min_temp: min(st.min_temp, new_temp)
    }
  end

  def step_turbines(st) do
    n = length(st.turbine_speeds)
    if n == 0, do: %{st | tick_count: st.tick_count + 1}, else: do_step(st, n)
  end

  defp do_step(st, n) do
    total_demand = st.demand_per_turbine * n
    actual_total = min(total_demand, st.pressure)
    actual_per = actual_total / n
    starved = if actual_total < total_demand * 0.99, do: 1, else: 0

    new_speeds = Enum.map(st.turbine_speeds, fn speed ->
      (speed + actual_per * st.accel) * (1 - st.friction)
    end)

    tick_power = Enum.map(new_speeds, fn speed ->
      eff = :math.exp(-:math.pow(speed - st.peak_speed, 2) / (2 * st.sigma * st.sigma))
      eff * st.max_eff * actual_per
    end) |> Enum.sum()

    %{st |
      turbine_speeds: new_speeds,
      pressure: max(st.pressure - actual_total, 0.0),
      total_power: st.total_power + tick_power,
      total_steam_consumed: st.total_steam_consumed + actual_total,
      total_ticks_starved: st.total_ticks_starved + starved,
      tick_count: st.tick_count + 1
    }
  end

  def record(st) do
    new_sh = Enum.zip(st.speed_histories, st.turbine_speeds)
      |> Enum.map(fn {h, s} -> [s | h] end)
    %{st |
      temp_history: [st.temperature | st.temp_history],
      pressure_history: [st.pressure | st.pressure_history]
    } |> Map.put(:speed_histories, new_sh)
  end

  def avg_power(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_power / st.tick_count)
  def starved_pct(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_ticks_starved / st.tick_count * 100)

  def avg_steam_rate(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_steam_produced / st.tick_count)
  def vented_pct(st), do: if(st.total_steam_produced == 0, do: 0.0,
    else: st.total_steam_vented / st.total_steam_produced * 100)

  def speed_range(st) do
    settled = hd(st.speed_histories) |> Enum.reverse() |> Enum.drop(120)
    if settled == [], do: {0.0, 0.0}, else: {Enum.min(settled), Enum.max(settled)}
  end
end

# =============================================================================

IO.puts("=" |> String.duplicate(82))
IO.puts("  ASYMMETRIC REACTOR HEATING — CAN THE PLAYER RUN HOTTER?")
IO.puts("=" |> String.duplicate(82))
IO.puts("")

peak = 1.5
accel = 1.0
base_friction = 0.10
base_max_eff = 480.0
base_sigma = 0.40
base_demand = peak * base_friction / (accel * (1 - base_friction))
duration = 720  # 3 full cells worth

IO.puts("  Base demand/turbine: #{Float.round(base_demand, 4)}")
IO.puts("  Steam rate formula: (temp - 100) / 100")
IO.puts("  Normal cycle: heat 60 ticks (100→200), cool 60 ticks (200→100)")
IO.puts("")

# =============================================================================
# PART 1: Different phase schedules
# =============================================================================

IO.puts("== PART 1: PHASE SCHEDULES ==")
IO.puts("")

# Each schedule is a repeating list of {direction, ticks}
schedules = [
  {"Standard H-C-H-C",
   [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}],
   100.0,
   "Normal: 100↔200, avg ~150"},

  {"2H-1C (asymmetric)",
   [{:heat, 60}, {:heat, 60}, {:cool, 60}],
   100.0,
   "100→200→300→200, avg ~200"},

  {"2H-2C (high range)",
   [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}],
   100.0,
   "100→200→300→200→100, avg ~200"},

  {"3H-2C",
   [{:heat, 60}, {:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}],
   100.0,
   "100→300→400→300→100, avg ~240"},

  {"Short H-C (30 tick phases)",
   [{:heat, 30}, {:cool, 30}, {:heat, 30}, {:cool, 30}],
   150.0,
   "150↔200, avg ~175, tighter swing"},

  {"Long H, short C",
   [{:heat, 90}, {:cool, 30}],
   100.0,
   "Heat 90t then cool 30t"},
]

IO.puts("  Schedule             | Temp Range | Avg Steam | 3T cap=2 | 3T cap=15 | Starv% | Vent%")
IO.puts("  " <> String.duplicate("-", 90))

Enum.each(schedules, fn {name, schedule, start_temp, _desc} ->
  # Run at cap=2 and cap=15
  results = Enum.map([2.0, 15.0], fn cap ->
    final = AsymSim.init(
      turbines: 3, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
      accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
      schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
      temp_rate: 1.667
    ) |> AsymSim.simulate(duration)

    {AsymSim.avg_power(final), AsymSim.starved_pct(final), AsymSim.vented_pct(final),
     AsymSim.avg_steam_rate(final), final.peak_temp, final.min_temp}
  end)

  [{pw2, st2, vt2, sr, tmax, tmin}, {pw15, st15, vt15, _, _, _}] = results

  IO.puts(
    "  #{String.pad_trailing(name, 22)} |" <>
    " #{String.pad_leading("#{Float.round(tmin, 0)}", 3)}-#{String.pad_leading("#{Float.round(tmax, 0)}", 3)} |" <>
    " #{String.pad_leading("#{Float.round(sr, 3)}", 9)} |" <>
    " #{String.pad_leading("#{Float.round(pw2, 0)}", 5)}W   |" <>
    " #{String.pad_leading("#{Float.round(pw15, 0)}", 5)}W   |" <>
    " #{String.pad_leading("#{Float.round(st2, 0)}/#{Float.round(st15, 0)}", 6)} |" <>
    " #{String.pad_leading("#{Float.round(vt2, 0)}/#{Float.round(vt15, 0)}", 5)}"
  )
end)

IO.puts("")
IO.puts("  (Starv%: cap=2/cap=15, Vent%: cap=2/cap=15)")
IO.puts("")

# =============================================================================
# PART 2: Detailed tick profile for asymmetric schedules
# =============================================================================

IO.puts("== PART 2: TICK PROFILES ==")
IO.puts("")

interesting = [
  {"Standard H-C-H-C", [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}], 100.0},
  {"2H-1C (asymmetric)", [{:heat, 60}, {:heat, 60}, {:cool, 60}], 100.0},
  {"2H-2C (high range)", [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}], 100.0},
]

Enum.each(interesting, fn {name, schedule, start_temp} ->
  IO.puts("  #{name}:")

  final = AsymSim.init(
    turbines: 3, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_demand,
    schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
    temp_rate: 1.667
  ) |> AsymSim.simulate(360)

  temps = Enum.reverse(final.temp_history)
  pressures = Enum.reverse(final.pressure_history)
  speeds = hd(final.speed_histories) |> Enum.reverse()

  IO.puts("  Tick | Temp   | Steam/t | Pressure | Speed  | Fed?")
  IO.puts("  " <> String.duplicate("-", 55))

  Enum.each(0..35, fn i ->
    t = i * 10
    if t < length(temps) do
      temp = Enum.at(temps, t)
      press = Enum.at(pressures, t)
      spd = Enum.at(speeds, t)
      sr = if temp > 100, do: (temp - 100) / 100, else: 0.0
      total_d = base_demand * 3
      fed = if press + sr >= total_d * 0.99, do: "YES", else: "NO "

      IO.puts(
        "  #{String.pad_leading("#{t}", 4)} |" <>
        " #{String.pad_leading("#{Float.round(temp, 1)}", 6)} |" <>
        " #{String.pad_leading("#{Float.round(sr, 3)}", 7)} |" <>
        " #{String.pad_leading("#{Float.round(press, 1)}", 8)} |" <>
        " #{String.pad_leading("#{Float.round(spd, 3)}", 6)} |" <>
        "  #{fed}"
      )
    end
  end)

  IO.puts("  Avg power: #{Float.round(AsymSim.avg_power(final), 0)}W")
  IO.puts("  Starved: #{Float.round(AsymSim.starved_pct(final), 0)}%")
  IO.puts("  Vented: #{Float.round(AsymSim.vented_pct(final), 0)}%")
  IO.puts("")
end)

# =============================================================================
# PART 3: More turbines for higher steam rate
# =============================================================================

IO.puts("== PART 3: TURBINE SCALING FOR HOTTER REACTORS ==")
IO.puts("")
IO.puts("  If the reactor runs hotter (more steam), can we add more turbines?")
IO.puts("  Standard: avg 0.5 steam/tick → 3 turbines at 0.167 demand each")
IO.puts("  2H-2C:    avg ~1.0 steam/tick → 6 turbines could be fed?")
IO.puts("")

Enum.each([
  {"Standard H-C-H-C", [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}], 100.0},
  {"2H-2C (high range)", [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}], 100.0},
], fn {name, schedule, start_temp} ->
  IO.puts("  #{name}:")

  # Quick: compute average steam
  test = AsymSim.init(
    turbines: 1, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
    accel: accel, peak_speed: peak, capacity: 100.0, demand: 0.001,
    schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
    temp_rate: 1.667
  ) |> AsymSim.simulate(duration)
  avg_sr = AsymSim.avg_steam_rate(test)
  max_turbs = Float.round(avg_sr / base_demand, 1)
  IO.puts("    Avg steam: #{Float.round(avg_sr, 3)}/tick → can feed ~#{max_turbs} turbines")

  IO.puts("    N | cap=2     | cap=15    | cap=30")
  IO.puts("    " <> String.duplicate("-", 45))

  Enum.each(1..10, fn n ->
    results = Enum.map([2.0, 15.0, 30.0], fn cap ->
      f = AsymSim.init(
        turbines: n, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
        accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
        schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
        temp_rate: 1.667
      ) |> AsymSim.simulate(duration)
      {AsymSim.avg_power(f), AsymSim.starved_pct(f)}
    end)

    IO.puts(
      "    #{String.pad_leading("#{n}", 2)} |" <>
      Enum.map_join(results, " |", fn {pw, st} ->
        " #{String.pad_leading("#{Float.round(pw, 0)}", 4)}W s=#{String.pad_leading("#{Float.round(st, 0)}", 2)}%"
      end)
    )
  end)

  IO.puts("")
end)

# =============================================================================
# PART 4: What does the player trade for hotter operation?
# =============================================================================

IO.puts("== PART 4: COST/BENEFIT OF HOTTER OPERATION ==")
IO.puts("")
IO.puts("  Running hotter means:")
IO.puts("  - More steam per tick → potentially more power")
IO.puts("  - More thermal consumables (more heating phases)")
IO.puts("  - Risk of hitting Critical (300) if timing slips")
IO.puts("  - Need more turbines to capture extra steam")
IO.puts("")

# Cost comparison per 240 ticks
IO.puts("  Per 240 ticks (1 nuclear cell):")
IO.puts("")

cost_scenarios = [
  {"Standard (H-C-H-C)", 2, 2, "2 heat + 2 cool phases"},
  {"2H-2C", 2, 2, "2 heat + 2 cool phases (same cost, diff timing)"},
  {"2H-1C (asymmetric)", 8, 4, "~8 heat + 4 cool per 720t = 2.67H + 1.33C per 240t"},
  {"3H-2C", 12, 8, "~12 heat + 8 cool per 1200t = 2.4H + 1.6C per 240t"},
]

# Actually let's compute properly based on schedule
IO.puts("  Schedule             | Phases/240t      | Regulators | Coolant | Opt Turbs | Power(c15)")
IO.puts("  " <> String.duplicate("-", 85))

schedules_v2 = [
  {"Standard H-C-H-C", [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}], 100.0, 240},
  {"2H-2C",            [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}], 100.0, 240},
  {"2H-1C",            [{:heat, 60}, {:heat, 60}, {:cool, 60}], 100.0, 180},
  {"3H-2C",            [{:heat, 60}, {:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}], 100.0, 300},
]

Enum.each(schedules_v2, fn {name, schedule, start_temp, cycle_len} ->
  # Count heats and cools in one cycle
  n_heat = Enum.count(schedule, fn {d, _} -> d == :heat end)
  n_cool = Enum.count(schedule, fn {d, _} -> d == :cool end)

  # Per 240 ticks: how many full cycles?
  cycles_per_cell = 240.0 / cycle_len
  regs_per_cell = n_heat * cycles_per_cell
  cools_per_cell = n_cool * cycles_per_cell

  # Find optimal turbine count
  results = Enum.map(1..12, fn n ->
    f = AsymSim.init(
      turbines: n, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_demand,
      schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
      temp_rate: 1.667
    ) |> AsymSim.simulate(duration)
    {n, AsymSim.avg_power(f)}
  end)
  {opt_n, opt_pw} = Enum.max_by(results, fn {_, p} -> p end)

  IO.puts(
    "  #{String.pad_trailing(name, 22)} |" <>
    " #{n_heat}H+#{n_cool}C/#{cycle_len}t" <>
    String.pad_trailing("", 8) <> "|" <>
    " #{String.pad_leading("#{Float.round(regs_per_cell, 1)}", 10)} |" <>
    " #{String.pad_leading("#{Float.round(cools_per_cell, 1)}", 7)} |" <>
    " #{String.pad_leading("#{opt_n}", 9)} |" <>
    " #{String.pad_leading("#{Float.round(opt_pw, 0)}", 5)}W"
  )
end)

IO.puts("")

# ROI comparison
IO.puts("  ROI comparison (at optimal turbine counts, cap=15):")
IO.puts("")

cell_cost = 43_271.2
thermal_per_reg = 1_184.8
thermal_per_cool = 1_323.5

Enum.each(schedules_v2, fn {name, schedule, start_temp, cycle_len} ->
  n_heat = Enum.count(schedule, fn {d, _} -> d == :heat end)
  n_cool = Enum.count(schedule, fn {d, _} -> d == :cool end)
  cycles_per_cell = 240.0 / cycle_len
  regs = n_heat * cycles_per_cell
  cools = n_cool * cycles_per_cell

  thermal_cost = regs * thermal_per_reg + cools * thermal_per_cool
  total_cost = cell_cost + thermal_cost

  results = Enum.map(1..12, fn n ->
    f = AsymSim.init(
      turbines: n, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_demand,
      schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
      temp_rate: 1.667
    ) |> AsymSim.simulate(duration)
    {n, AsymSim.avg_power(f)}
  end)
  {opt_n, opt_pw} = Enum.max_by(results, fn {_, p} -> p end)

  gross = opt_pw * 240
  roi = gross / total_cost

  IO.puts(
    "  #{String.pad_trailing(name, 22)}" <>
    " #{opt_n}T:" <>
    " #{String.pad_leading("#{Float.round(opt_pw, 0)}", 4)}W" <>
    " gross=#{String.pad_leading("#{Float.round(gross, 0)}", 6)}Wt" <>
    " cost=#{String.pad_leading("#{Float.round(total_cost, 0)}", 6)}Wt" <>
    " ROI=#{Float.round(roi, 2)}x" <>
    "  peak=#{Float.round(start_temp + n_heat * 60 * 1.667, 0)}"
  )
end)

IO.puts("")

# =============================================================================
# PART 5: The critical temperature question
# =============================================================================

IO.puts("== PART 5: CRITICAL TEMPERATURE RISK ==")
IO.puts("")
IO.puts("  Current design: Critical = 300 (shutdown if exceeded)")
IO.puts("  Standard cycle peaks at 200 — safe margin of 100")
IO.puts("")

Enum.each(schedules_v2, fn {name, schedule, start_temp, _cycle_len} ->
  n_heat = Enum.count(schedule, fn {d, _} -> d == :heat end)
  peak_t = start_temp + n_heat * 60 * 1.667

  margin = 300 - peak_t
  risk = cond do
    margin > 50 -> "safe"
    margin > 0 -> "RISKY (#{Float.round(margin, 0)} margin)"
    true -> "MELTDOWN (exceeds critical by #{Float.round(-margin, 0)})"
  end

  IO.puts("  #{String.pad_trailing(name, 22)} peak=#{String.pad_leading("#{Float.round(peak_t, 0)}", 4)}  #{risk}")
end)

IO.puts("")
IO.puts("  The 2H-1C and 3H-2C schedules exceed Critical (300)!")
IO.puts("  The player CAN'T run these without raising Critical or accepting shutdown risk.")
IO.puts("")
IO.puts("  Design options:")
IO.puts("  a) Critical = 300 is fixed → only standard and 2H-2C are viable")
IO.puts("  b) Critical is upgradeable (heat-resistant reactor casing?)")
IO.puts("  c) Add a 'regulator setpoint' building that controls phase switching")
IO.puts("  d) Wider temp range with diminishing steam returns above danger")
IO.puts("")

# =============================================================================
# PART 6: The 2H-2C pattern is actually the same as standard!
# =============================================================================

IO.puts("== PART 6: IS 2H-2C DIFFERENT FROM STANDARD? ==")
IO.puts("")
IO.puts("  Standard: H(60)-C(60)-H(60)-C(60) → 100→200→100→200→100")
IO.puts("  2H-2C:    H(60)-H(60)-C(60)-C(60) → 100→200→300→200→100")
IO.puts("")
IO.puts("  Wait — 2H-2C peaks at 300! That's Critical!")
IO.puts("  Unless the player has upgraded Critical temp...")
IO.puts("")
IO.puts("  Let's compare them assuming Critical is raised to 350:")
IO.puts("")

# Both run safely if critical is high enough
Enum.each([3, 4, 5, 6], fn n ->
  Enum.each([
    {"H-C-H-C", [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}], 100.0},
    {"2H-2C",   [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}], 100.0},
  ], fn {name, schedule, start_temp} ->
    f = AsymSim.init(
      turbines: n, friction: base_friction, max_eff: base_max_eff, sigma: base_sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_demand,
      schedule: schedule, start_temp: start_temp, operating_temp: 100.0,
      temp_rate: 1.667
    ) |> AsymSim.simulate(duration)

    IO.puts(
      "  #{String.pad_trailing(name, 10)} #{n}T:" <>
      " #{String.pad_leading("#{Float.round(AsymSim.avg_power(f), 0)}", 4)}W" <>
      " starved=#{Float.round(AsymSim.starved_pct(f), 0)}%" <>
      " vented=#{Float.round(AsymSim.vented_pct(f), 0)}%"
    )
  end)
  IO.puts("")
end)

IO.puts("")
IO.puts("=" |> String.duplicate(82))
IO.puts("  CONCLUSIONS")
IO.puts("=" |> String.duplicate(82))
IO.puts("")
IO.puts("  1. Hotter operation produces more steam → more potential power")
IO.puts("  2. But it requires more turbines to capture the extra steam")
IO.puts("  3. Asymmetric schedules (2H-1C, 3H-2C) exceed Critical=300")
IO.puts("  4. 2H-2C peaks at 300 — exactly at Critical, very risky")
IO.puts("  5. The player COULD do this if Critical temp is upgradeable")
IO.puts("  6. This creates a high-risk/high-reward upgrade path:")
IO.puts("     - Base: safe 100↔200 operation, reliable but capped")
IO.puts("     - Upgraded casing: 100↔300 range, more steam, more turbines needed")
IO.puts("     - Extreme: 3H-2C with reinforced reactor, peak power but meltdown risk")
IO.puts("")
