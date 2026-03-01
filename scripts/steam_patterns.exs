# scripts/steam_patterns.exs
#
# Exploration of additional interesting steam/reactor patterns beyond
# the basic standard and 2H-2C setups.
#
# Patterns explored:
#   1. Multi-reactor configurations (2x, 3x) with various offsets
#   2. Bearing upgrades combined with 2H-2C
#   3. Mixed-mode reactors (one standard + one 2H-2C on shared header)
#   4. Short-phase cycling (faster switching, tighter temp band)
#   5. Player-controlled temperature setpoints

defmodule PatternSim do
  defstruct [
    :pressure, :capacity,
    :reactors,          # list of reactor state maps
    :turbine_speeds, :accel, :friction,
    :max_eff, :peak_speed, :sigma,
    :demand_per_turbine,
    :total_power, :total_steam_produced, :total_steam_consumed,
    :total_steam_vented, :total_ticks_starved, :tick_count,
    :peak_temp, :min_temp,
    :temp_history, :pressure_history
  ]

  defmodule Reactor do
    defstruct [
      :temperature, :operating_temp, :temp_rate,
      :phase_schedule, :phase_index, :phase_tick,
      :tick_offset  # delay before this reactor starts cycling
    ]
  end

  def init(opts) do
    n = Keyword.fetch!(opts, :turbines)
    reactors = Keyword.fetch!(opts, :reactors)
      |> Enum.map(fn r ->
        %Reactor{
          temperature: Keyword.get(r, :start_temp, 100.0),
          operating_temp: Keyword.get(r, :operating_temp, 100.0),
          temp_rate: Keyword.get(r, :temp_rate, 1.667),
          phase_schedule: Keyword.fetch!(r, :schedule),
          phase_index: 0,
          phase_tick: 0,
          tick_offset: Keyword.get(r, :offset, 0)
        }
      end)

    %PatternSim{
      pressure: 0.0,
      capacity: Keyword.get(opts, :capacity, 15.0),
      reactors: reactors,
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
      peak_temp: 0.0, min_temp: 999.0,
      temp_history: [], pressure_history: []
    }
  end

  def simulate(st, duration) do
    Enum.reduce(1..duration, st, fn _, s ->
      s |> step_reactors() |> step_turbines() |> record()
    end)
  end

  def step_reactors(st) do
    {new_reactors, total_steam} =
      Enum.map_reduce(st.reactors, 0.0, fn r, steam_acc ->
        if st.tick_count < r.tick_offset do
          # Reactor hasn't started yet — just accumulate idle time
          {r, steam_acc}
        else
          schedule = r.phase_schedule
          {direction, phase_len} = Enum.at(schedule, rem(r.phase_index, length(schedule)))

          delta = case direction do
            :heat -> r.temp_rate
            :cool -> -r.temp_rate
          end

          new_temp = max(r.temperature + delta, 0.0)

          {new_idx, new_pt} =
            if r.phase_tick >= phase_len - 1,
              do: {r.phase_index + 1, 0},
              else: {r.phase_index, r.phase_tick + 1}

          steam = if new_temp > r.operating_temp,
            do: (new_temp - r.operating_temp) / 100.0, else: 0.0

          {%{r | temperature: new_temp, phase_index: new_idx, phase_tick: new_pt},
           steam_acc + steam}
        end
      end)

    new_p = st.pressure + total_steam
    vented = max(new_p - st.capacity, 0.0)

    peak_t = Enum.map(new_reactors, & &1.temperature) |> Enum.max()
    min_t = Enum.map(new_reactors, & &1.temperature) |> Enum.min()

    %{st |
      reactors: new_reactors,
      pressure: min(new_p, st.capacity),
      total_steam_produced: st.total_steam_produced + total_steam,
      total_steam_vented: st.total_steam_vented + vented,
      peak_temp: max(st.peak_temp, peak_t),
      min_temp: min(st.min_temp, min_t)
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
    %{st |
      temp_history: [hd(st.reactors).temperature | st.temp_history],
      pressure_history: [st.pressure | st.pressure_history]
    }
  end

  def avg_power(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_power / st.tick_count)
  def starved_pct(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_ticks_starved / st.tick_count * 100)
  def vented_pct(st), do: if(st.total_steam_produced == 0, do: 0.0,
    else: st.total_steam_vented / st.total_steam_produced * 100)
  def avg_steam(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_steam_produced / st.tick_count)
end

# =============================================================================

IO.puts("=" |> String.duplicate(82))
IO.puts("  ADVANCED REACTOR PATTERNS — EXPLORING THE DESIGN SPACE")
IO.puts("=" |> String.duplicate(82))
IO.puts("")

peak = 1.5
accel = 1.0
duration = 960  # 4 cells worth for good averages

# Bearing tier definitions
tiers = [
  {"No bearings", 0.10, 480.0, 0.40},
  {"Bronze",      0.07, 720.0, 0.55},
  {"Steel",       0.05, 960.0, 0.75},
  {"Titanium",    0.027, 1440.0, 1.00},
]

standard_schedule = [{:heat, 60}, {:cool, 60}, {:heat, 60}, {:cool, 60}]
asym_schedule = [{:heat, 60}, {:heat, 60}, {:cool, 60}, {:cool, 60}]

# =============================================================================
# PATTERN 1: Triple reactor configurations
# =============================================================================

IO.puts("== PATTERN 1: TRIPLE REACTOR WITH 1/3-CYCLE OFFSET ==")
IO.puts("")
IO.puts("  Two reactors offset by 1/2 cycle nearly eliminates starvation.")
IO.puts("  Does three reactors offset by 1/3 cycle do even better?")
IO.puts("  Standard cycle = 120 ticks, so 1/3 offset = 40 ticks.")
IO.puts("")

base_f = 0.10
base_me = 480.0
base_s = 0.40
base_d = peak * base_f / (accel * (1 - base_f))

make_reactor = fn schedule, offset, start_temp ->
  [schedule: schedule, offset: offset, start_temp: start_temp, operating_temp: 100.0, temp_rate: 1.667]
end

configs = [
  {"1 reactor",    1, [make_reactor.(standard_schedule, 0, 100.0)], 3},
  {"2R half-offset", 2, [
    make_reactor.(standard_schedule, 0, 100.0),
    make_reactor.(standard_schedule, 60, 100.0)
  ], 6},
  {"3R third-offset", 3, [
    make_reactor.(standard_schedule, 0, 100.0),
    make_reactor.(standard_schedule, 40, 100.0),
    make_reactor.(standard_schedule, 80, 100.0)
  ], 9},
]

IO.puts("  Config              | Turbines | Power  | Per-reactor | Starved | Vented | Avg Steam")
IO.puts("  " <> String.duplicate("-", 80))

Enum.each(configs, fn {name, n_reactors, reactors, turbines} ->
  f = PatternSim.init(
    turbines: turbines, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: reactors
  ) |> PatternSim.simulate(duration)

  per_r = PatternSim.avg_power(f) / n_reactors

  IO.puts(
    "  #{String.pad_trailing(name, 21)} |" <>
    " #{String.pad_leading("#{turbines}", 8)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(per_r, 0)}", 10)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.vented_pct(f), 0)}%", 6)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_steam(f), 2)}", 9)}"
  )
end)

IO.puts("")

# Also try: does 3R even need tanks?
IO.puts("  Three reactors — header capacity sweep:")
IO.puts("  Cap  | Power  | Starved")
IO.puts("  " <> String.duplicate("-", 30))

Enum.each([2, 5, 10, 15, 20, 30], fn cap ->
  f = PatternSim.init(
    turbines: 9, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: cap * 1.0, demand: base_d,
    reactors: [
      make_reactor.(standard_schedule, 0, 100.0),
      make_reactor.(standard_schedule, 40, 100.0),
      make_reactor.(standard_schedule, 80, 100.0)
    ]
  ) |> PatternSim.simulate(duration)

  IO.puts(
    "  #{String.pad_leading("#{cap}", 4)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)}"
  )
end)

IO.puts("")

# =============================================================================
# PATTERN 2: Bearing upgrades + 2H-2C interaction
# =============================================================================

IO.puts("== PATTERN 2: BEARING UPGRADES WITH 2H-2C ==")
IO.puts("")
IO.puts("  How do bearing upgrades interact with 2H-2C?")
IO.puts("  2H-2C doubles steam → double the turbines at each tier.")
IO.puts("")

IO.puts("  Tier           | Std Opt T | Std Power | 2H-2C Opt T | 2H-2C Power | Gain")
IO.puts("  " <> String.duplicate("-", 75))

Enum.each(tiers, fn {tier_name, friction, max_eff, sigma} ->
  demand = peak * friction / (accel * (1 - friction))

  # Find optimal for standard
  std_results = Enum.map(1..20, fn n ->
    f = PatternSim.init(
      turbines: n, friction: friction, max_eff: max_eff, sigma: sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
      reactors: [make_reactor.(standard_schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)
    {n, PatternSim.avg_power(f)}
  end)
  {std_n, std_pw} = Enum.max_by(std_results, fn {_, p} -> p end)

  # Find optimal for 2H-2C
  asym_results = Enum.map(1..30, fn n ->
    f = PatternSim.init(
      turbines: n, friction: friction, max_eff: max_eff, sigma: sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
      reactors: [make_reactor.(asym_schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)
    {n, PatternSim.avg_power(f)}
  end)
  {asym_n, asym_pw} = Enum.max_by(asym_results, fn {_, p} -> p end)

  gain = (asym_pw - std_pw) / std_pw * 100

  IO.puts(
    "  #{String.pad_trailing(tier_name, 16)} |" <>
    " #{String.pad_leading("#{std_n}", 9)} |" <>
    " #{String.pad_leading("#{Float.round(std_pw, 0)}", 8)}W |" <>
    " #{String.pad_leading("#{asym_n}", 11)} |" <>
    " #{String.pad_leading("#{Float.round(asym_pw, 0)}", 10)}W |" <>
    " +#{Float.round(gain, 0)}%"
  )
end)

IO.puts("")

# =============================================================================
# PATTERN 3: Mixed-mode reactors (standard + 2H-2C on shared header)
# =============================================================================

IO.puts("== PATTERN 3: MIXED-MODE REACTORS ==")
IO.puts("")
IO.puts("  One standard reactor + one 2H-2C reactor on shared header.")
IO.puts("  The standard produces 0.5 steam/tick avg, the 2H-2C produces 1.0.")
IO.puts("  Total: 1.5 steam/tick → ~9 turbines at base bearings.")
IO.puts("  Does the standard reactor smooth out the 2H-2C's wider swings?")
IO.puts("")

mixed_configs = [
  {"2× standard (offset)", [
    make_reactor.(standard_schedule, 0, 100.0),
    make_reactor.(standard_schedule, 60, 100.0)
  ], "baseline for comparison"},
  {"1× std + 1× 2H-2C", [
    make_reactor.(standard_schedule, 0, 100.0),
    make_reactor.(asym_schedule, 0, 100.0)
  ], "mixed, no offset"},
  {"1× std + 1× 2H-2C (offset 60)", [
    make_reactor.(standard_schedule, 0, 100.0),
    make_reactor.(asym_schedule, 60, 100.0)
  ], "mixed, offset by half std cycle"},
  {"2× 2H-2C (offset 60)", [
    make_reactor.(asym_schedule, 0, 100.0),
    make_reactor.(asym_schedule, 60, 100.0)
  ], "both hotter, offset by half cycle"},
  {"2× 2H-2C (offset 120)", [
    make_reactor.(asym_schedule, 0, 100.0),
    make_reactor.(asym_schedule, 120, 100.0)
  ], "both hotter, offset by half 2H-2C cycle"},
]

Enum.each(mixed_configs, fn {name, reactors, desc} ->
  IO.puts("  #{name} (#{desc}):")

  # Sweep turbines to find optimal
  results = Enum.map(1..18, fn n ->
    f = PatternSim.init(
      turbines: n, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: reactors
    ) |> PatternSim.simulate(duration)
    {n, PatternSim.avg_power(f), PatternSim.starved_pct(f), PatternSim.vented_pct(f)}
  end)

  IO.puts("    N | Power  | Starved | Vented")
  IO.puts("    " <> String.duplicate("-", 35))

  # Show a selection of turbine counts around the optimum
  {opt_n, _, _, _} = Enum.max_by(results, fn {_, p, _, _} -> p end)
  show_range = Enum.filter(results, fn {n, _, _, _} ->
    n in [3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16]
  end)

  Enum.each(show_range, fn {n, pw, st, vt} ->
    marker = if n == opt_n, do: " ★", else: ""
    IO.puts(
      "    #{String.pad_leading("#{n}", 2)} |" <>
      " #{String.pad_leading("#{Float.round(pw, 0)}", 5)}W |" <>
      " #{String.pad_leading("#{Float.round(st, 0)}%", 7)} |" <>
      " #{String.pad_leading("#{Float.round(vt, 0)}%", 6)}#{marker}"
    )
  end)
  IO.puts("")
end)

# =============================================================================
# PATTERN 4: Short-phase cycling
# =============================================================================

IO.puts("== PATTERN 4: SHORT-PHASE CYCLING ==")
IO.puts("")
IO.puts("  What if the player uses shorter phases? e.g. 30-tick instead of 60.")
IO.puts("  Tighter temperature band → less oscillation → less starvation.")
IO.puts("  But: more phase switches means more consumable usage?")
IO.puts("")
IO.puts("  Key question: does phase length affect consumable cost?")
IO.puts("  If 1 regulator/coolant per phase: shorter phases = higher cost.")
IO.puts("  If consumable cost is per-cell (fixed 240t): same cost regardless.")
IO.puts("")

phase_lengths = [15, 20, 30, 45, 60, 90, 120]

IO.puts("  Phase | Temp Range | Consumables/240t | 3T Power | Starved | 3T cap=2 Starved")
IO.puts("  " <> String.duplicate("-", 80))

Enum.each(phase_lengths, fn pl ->
  # Number of phases in 240 ticks
  phases_per_cell = 240.0 / pl
  # Assuming H-C-H-C pattern, half are heat, half cool
  regs_per_cell = phases_per_cell / 2
  cools_per_cell = phases_per_cell / 2

  # Starting temp: midpoint of the range
  # With phase_len ticks at 1.667/tick, temp swing = pl * 1.667
  swing = pl * 1.667
  # For symmetric H-C, reactor oscillates between (center - swing/2) and (center + swing/2)
  # We want center at 150 (midpoint of 100-200), so start_temp = 150
  # But actually: start at operating_temp (100), heat for pl ticks → 100 + swing
  # Then cool for pl → back to 100. Range: 100 to 100+swing.
  peak_temp = 100 + swing
  avg_temp = 100 + swing / 2

  schedule = [{:heat, pl}, {:cool, pl}, {:heat, pl}, {:cool, pl}]

  # cap=15
  f15 = PatternSim.init(
    turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: [make_reactor.(schedule, 0, 100.0)]
  ) |> PatternSim.simulate(duration)

  # cap=2
  f2 = PatternSim.init(
    turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 2.0, demand: base_d,
    reactors: [make_reactor.(schedule, 0, 100.0)]
  ) |> PatternSim.simulate(duration)

  IO.puts(
    "  #{String.pad_leading("#{pl}t", 5)} |" <>
    " #{String.pad_leading("#{Float.round(100.0, 0)}", 3)}-#{String.pad_leading("#{Float.round(peak_temp, 0)}", 3)} |" <>
    " #{String.pad_leading("#{Float.round(regs_per_cell, 1)}R + #{Float.round(cools_per_cell, 1)}C", 16)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f15), 0)}", 7)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f15), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f2), 0)}%", 7)}"
  )
end)

IO.puts("")
IO.puts("  Note: if consumables are per-phase, shorter phases are MUCH more expensive.")
IO.puts("  If consumables are per-cell, shorter phases are free optimization.")
IO.puts("  Current design: 1 consumable per phase → shorter phases cost more.")
IO.puts("")

# What if we keep same consumable budget (2 reg + 2 cool per cell) but use short phases?
IO.puts("  Alternative: phase length doesn't change consumable rate")
IO.puts("  (regulators/coolant last proportionally shorter at shorter phases)")
IO.puts("  → Short phases are a free optimization if consumable cost scales with phase length")
IO.puts("")

# =============================================================================
# PATTERN 5: Temperature setpoint control
# =============================================================================

IO.puts("== PATTERN 5: PLAYER-CONTROLLED TEMPERATURE SETPOINT ==")
IO.puts("")
IO.puts("  What if the player can choose the 'switch temperature' via a building?")
IO.puts("  Default: switch at Danger (200). But player could set it lower (150)")
IO.puts("  or leave it at 200. Lower setpoint → tighter range → less starvation.")
IO.puts("")

setpoints = [125, 150, 175, 200, 250, 300]

IO.puts("  Setpoint | Temp Range | Avg Steam | 3T Power(c15) | Starved | 3T Power(c2) | Starved")
IO.puts("  " <> String.duplicate("-", 85))

Enum.each(setpoints, fn sp ->
  # Ticks to reach setpoint from 100: (sp - 100) / 1.667
  heat_ticks = round((sp - 100) / 1.667)
  # Same ticks to cool back down
  cool_ticks = heat_ticks

  if heat_ticks > 0 do
    schedule = [{:heat, heat_ticks}, {:cool, cool_ticks}]

    f15 = PatternSim.init(
      turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [make_reactor.(schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)

    f2 = PatternSim.init(
      turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 2.0, demand: base_d,
      reactors: [make_reactor.(schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)

    peak_temp = 100 + heat_ticks * 1.667

    IO.puts(
      "  #{String.pad_leading("#{sp}", 8)} |" <>
      " #{String.pad_leading("100", 3)}-#{String.pad_leading("#{Float.round(peak_temp, 0)}", 3)} |" <>
      " #{String.pad_leading("#{Float.round(PatternSim.avg_steam(f15), 3)}", 9)} |" <>
      " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f15), 0)}", 13)}W |" <>
      " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f15), 0)}%", 7)} |" <>
      " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f2), 0)}", 13)}W |" <>
      " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f2), 0)}%", 7)}"
    )
  end
end)

IO.puts("")
IO.puts("  Higher setpoints produce more steam but wider oscillation → more starvation.")
IO.puts("  With 3 turbines tuned for 0.5 steam avg, setpoints >200 waste steam (need more turbines).")
IO.puts("")

# What about optimal turbine count for each setpoint?
IO.puts("  Optimal turbine counts per setpoint (cap=15):")
IO.puts("  Setpoint | Opt T | Power  | Starved | Avg Steam")
IO.puts("  " <> String.duplicate("-", 55))

Enum.each(setpoints, fn sp ->
  heat_ticks = round((sp - 100) / 1.667)
  cool_ticks = heat_ticks

  if heat_ticks > 0 do
    schedule = [{:heat, heat_ticks}, {:cool, cool_ticks}]

    results = Enum.map(1..20, fn n ->
      f = PatternSim.init(
        turbines: n, friction: base_f, max_eff: base_me, sigma: base_s,
        accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
        reactors: [make_reactor.(schedule, 0, 100.0)]
      ) |> PatternSim.simulate(duration)
      {n, PatternSim.avg_power(f), PatternSim.starved_pct(f), PatternSim.avg_steam(f)}
    end)

    {opt_n, opt_pw, opt_st, opt_sr} = Enum.max_by(results, fn {_, p, _, _} -> p end)

    IO.puts(
      "  #{String.pad_leading("#{sp}", 8)} |" <>
      " #{String.pad_leading("#{opt_n}", 5)} |" <>
      " #{String.pad_leading("#{Float.round(opt_pw, 0)}", 5)}W |" <>
      " #{String.pad_leading("#{Float.round(opt_st, 0)}%", 7)} |" <>
      " #{String.pad_leading("#{Float.round(opt_sr, 3)}", 9)}"
    )
  end
end)

IO.puts("")

# =============================================================================
# PATTERN 6: 2H-2C with dual reactor offset
# =============================================================================

IO.puts("== PATTERN 6: 2H-2C WITH DUAL REACTOR OFFSET ==")
IO.puts("")
IO.puts("  Standard dual offset: offset by 60 (half of 120-tick cycle)")
IO.puts("  2H-2C cycle is 240 ticks. What's the optimal offset?")
IO.puts("")

offsets = [30, 60, 90, 120, 150, 180]

IO.puts("  Offset | 16T Power | Starved | Vented | Avg Steam")
IO.puts("  " <> String.duplicate("-", 55))

Enum.each(offsets, fn offset ->
  f = PatternSim.init(
    turbines: 16, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: [
      make_reactor.(asym_schedule, 0, 100.0),
      make_reactor.(asym_schedule, offset, 100.0)
    ]
  ) |> PatternSim.simulate(duration)

  IO.puts(
    "  #{String.pad_leading("#{offset}t", 6)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 8)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.vented_pct(f), 0)}%", 6)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_steam(f), 2)}", 9)}"
  )
end)

IO.puts("")

# Optimal turbine count for dual 2H-2C at best offset
IO.puts("  Dual 2H-2C reactor — turbine sweep at best offset:")

# First find best offset
best_offset = Enum.max_by(offsets, fn offset ->
  f = PatternSim.init(
    turbines: 16, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: [
      make_reactor.(asym_schedule, 0, 100.0),
      make_reactor.(asym_schedule, offset, 100.0)
    ]
  ) |> PatternSim.simulate(duration)
  PatternSim.avg_power(f)
end)

IO.puts("  Best offset: #{best_offset}t")
IO.puts("")
IO.puts("    N | Power  | Starved | Per-reactor")
IO.puts("    " <> String.duplicate("-", 40))

Enum.each([6, 8, 10, 12, 14, 16, 18, 20], fn n ->
  f = PatternSim.init(
    turbines: n, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: [
      make_reactor.(asym_schedule, 0, 100.0),
      make_reactor.(asym_schedule, best_offset, 100.0)
    ]
  ) |> PatternSim.simulate(duration)

  per_r = PatternSim.avg_power(f) / 2

  IO.puts(
    "    #{String.pad_leading("#{n}", 2)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(per_r, 0)}", 10)}W"
  )
end)

IO.puts("")

# =============================================================================
# PATTERN 7: Deep dive on dual 2H-2C at offset 120 (the sweet spot)
# =============================================================================

IO.puts("== PATTERN 7: DUAL 2H-2C AT OFFSET 120 — DEEP DIVE ==")
IO.puts("")
IO.puts("  Offset 120 = half of 240-tick 2H-2C cycle.")
IO.puts("  When reactor A is in its two heating phases, reactor B is in its two cooling phases.")
IO.puts("  This should smooth steam output similarly to standard dual-offset.")
IO.puts("")

IO.puts("  Turbine sweep (cap=15):")
IO.puts("    N  | Power  | Starved | Vented | Per-reactor")
IO.puts("    " <> String.duplicate("-", 50))

Enum.each(4..20, fn n ->
  f = PatternSim.init(
    turbines: n, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
    reactors: [
      make_reactor.(asym_schedule, 0, 100.0),
      make_reactor.(asym_schedule, 120, 100.0)
    ]
  ) |> PatternSim.simulate(duration)

  per_r = PatternSim.avg_power(f) / 2

  IO.puts(
    "    #{String.pad_leading("#{n}", 2)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.vented_pct(f), 0)}%", 6)} |" <>
    " #{String.pad_leading("#{Float.round(per_r, 0)}", 10)}W"
  )
end)

IO.puts("")

# Header capacity sweep at the optimal turbine count
IO.puts("  Capacity sweep at 12 turbines:")
IO.puts("    Cap | Power  | Starved | Vented")
IO.puts("    " <> String.duplicate("-", 35))

Enum.each([2, 5, 10, 15, 20, 30, 50], fn cap ->
  f = PatternSim.init(
    turbines: 12, friction: base_f, max_eff: base_me, sigma: base_s,
    accel: accel, peak_speed: peak, capacity: cap * 1.0, demand: base_d,
    reactors: [
      make_reactor.(asym_schedule, 0, 100.0),
      make_reactor.(asym_schedule, 120, 100.0)
    ]
  ) |> PatternSim.simulate(duration)

  IO.puts(
    "    #{String.pad_leading("#{cap}", 3)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.vented_pct(f), 0)}%", 6)}"
  )
end)

IO.puts("")

# =============================================================================
# PATTERN 8: The full upgrade ladder — summary comparison
# =============================================================================

IO.puts("== PATTERN 8: FULL UPGRADE LADDER COMPARISON ==")
IO.puts("")
IO.puts("  Every player configuration from simplest to most complex (base bearings):")
IO.puts("")

ladder = [
  {"Bare minimum (1R 3T cap=2)", fn ->
    PatternSim.init(
      turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 2.0, demand: base_d,
      reactors: [make_reactor.(standard_schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)
  end, 1, 3, "1R+3T"},

  {"+ Pressure tank (1R 3T cap=15)", fn ->
    PatternSim.init(
      turbines: 3, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [make_reactor.(standard_schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)
  end, 1, 3, "1R+3T+tank"},

  {"+ Dual offset (2R 6T cap=15)", fn ->
    PatternSim.init(
      turbines: 6, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [
        make_reactor.(standard_schedule, 0, 100.0),
        make_reactor.(standard_schedule, 60, 100.0)
      ]
    ) |> PatternSim.simulate(duration)
  end, 2, 6, "2R+6T+tank"},

  {"+ Reinforced (1R 2H-2C 8T cap=15)", fn ->
    PatternSim.init(
      turbines: 8, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [make_reactor.(asym_schedule, 0, 100.0)]
    ) |> PatternSim.simulate(duration)
  end, 1, 8, "1R+8T+tank+casing"},

  {"+ Dual 2H-2C offset (2R 12T cap=15)", fn ->
    PatternSim.init(
      turbines: 12, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [
        make_reactor.(asym_schedule, 0, 100.0),
        make_reactor.(asym_schedule, 120, 100.0)
      ]
    ) |> PatternSim.simulate(duration)
  end, 2, 12, "2R+12T+tank+2×casing"},

  {"+ Triple std offset (3R 9T cap=15)", fn ->
    PatternSim.init(
      turbines: 9, friction: base_f, max_eff: base_me, sigma: base_s,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: base_d,
      reactors: [
        make_reactor.(standard_schedule, 0, 100.0),
        make_reactor.(standard_schedule, 40, 100.0),
        make_reactor.(standard_schedule, 80, 100.0)
      ]
    ) |> PatternSim.simulate(duration)
  end, 3, 9, "3R+9T+tank"},
]

IO.puts("  Setup                                | Bldgs | Power  | /reactor | Starved | ROI est")
IO.puts("  " <> String.duplicate("-", 80))

cell_cost = 43_271.2
thermal_cost_std = 2 * 1_184.8 + 2 * 1_323.5  # 2 reg + 2 cool per reactor per cell
thermal_cost_asym = thermal_cost_std  # same for 2H-2C (same number of consumables)

Enum.each(ladder, fn {name, sim_fn, n_reactors, n_turbines, _desc} ->
  f = sim_fn.()
  per_r = PatternSim.avg_power(f) / n_reactors
  total_bldgs = n_reactors + n_turbines + 1  # +1 for tank

  gross = PatternSim.avg_power(f) * 240
  cost = n_reactors * (cell_cost + thermal_cost_std)
  roi = gross / cost

  IO.puts(
    "  #{String.pad_trailing(name, 38)} |" <>
    " #{String.pad_leading("#{total_bldgs}", 5)} |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.avg_power(f), 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(per_r, 0)}", 7)}W |" <>
    " #{String.pad_leading("#{Float.round(PatternSim.starved_pct(f), 0)}%", 7)} |" <>
    " #{String.pad_leading("#{Float.round(roi, 2)}", 7)}x"
  )
end)

IO.puts("")
IO.puts("  Note: ROI = (avg_power × 240 ticks) / (N_reactors × cell_cost_per_reactor)")
IO.puts("  Buildings = reactors + turbines + 1 tank")
IO.puts("")

# =============================================================================
IO.puts("=" |> String.duplicate(82))
IO.puts("  SUMMARY OF FINDINGS")
IO.puts("=" |> String.duplicate(82))
IO.puts("")
IO.puts("  Run this script with: elixir scripts/steam_patterns.exs")
IO.puts("")
