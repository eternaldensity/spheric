# scripts/steam_pressure.exs
#
# Steam pressure model v3 — Fixed demand, variable supply.
#
# Key insight from v2: when turbines draw proportional to pressure,
# the power formula (eff * max_eff * steam_drawn) self-balances because
# high steam → high draw → overspeed but also more fuel. Smoothing doesn't help.
#
# v3 changes: turbines have a FIXED demand rate. The header pressure determines
# whether that demand can be met.
#
#   - Each turbine wants `demand` steam per tick (configurable)
#   - If header pressure >= total_demand: each turbine gets exactly `demand`
#   - If header pressure < total_demand: rationed proportionally (starved)
#   - Power = eff(speed) * max_eff * steam_actually_received
#
# This creates meaningful dynamics:
#   - During hot phases: surplus steam → header pressure rises → buffer fills
#   - During cold phases: deficit → header drains → turbines may starve
#   - Bigger buffer = more runway during cold phases
#   - Phase-offset reactors = smoother combined supply

defmodule SteamSim do
  defstruct [
    :pressure, :capacity,
    :reactors,
    :turbine_speeds, :accel, :friction,
    :max_eff, :peak_speed, :sigma,
    :demand_per_turbine,  # fixed steam demand per turbine per tick
    :total_power, :total_steam_produced, :total_steam_consumed,
    :total_steam_vented, :total_ticks_starved, :tick_count,
    :power_history, :pressure_history, :speed_histories, :temp_history
  ]

  defmodule Reactor do
    defstruct [:temperature, :operating_temp, :danger_temp,
               :heating?, :phase_tick, :phase_length, :temp_rate]
  end

  def init(opts) do
    n_turb = Keyword.fetch!(opts, :turbines)
    n_react = Keyword.get(opts, :reactors, 1)
    phase_length = Keyword.get(opts, :phase_length, 60)
    offsets = Keyword.get(opts, :phase_offsets, List.duplicate(0, n_react))
    start_temp = Keyword.get(opts, :start_temp, Keyword.get(opts, :operating_temp, 100.0))
    temp_rate = Keyword.get(opts, :temp_rate, 1.667)
    op_temp = Keyword.get(opts, :operating_temp, 100.0)
    dang_temp = Keyword.get(opts, :danger_temp, 200.0)

    reactors = Enum.map(offsets, fn offset ->
      if offset == 0 do
        %Reactor{temperature: start_temp, operating_temp: op_temp, danger_temp: dang_temp,
                 heating?: true, phase_tick: 0, phase_length: phase_length, temp_rate: temp_rate}
      else
        {t, h, p} = Enum.reduce(1..offset, {start_temp, true, 0}, fn _, {t, h, p} ->
          advance_tick(t, h, p, temp_rate, phase_length, op_temp, dang_temp)
        end)
        %Reactor{temperature: t, operating_temp: op_temp, danger_temp: dang_temp,
                 heating?: h, phase_tick: p, phase_length: phase_length, temp_rate: temp_rate}
      end
    end)

    %SteamSim{
      pressure: Keyword.get(opts, :start_pressure, 0.0),
      capacity: Keyword.get(opts, :capacity, 5.0),
      reactors: reactors,
      turbine_speeds: List.duplicate(0.0, n_turb),
      accel: Keyword.get(opts, :accel, 1.0),
      friction: Keyword.fetch!(opts, :friction),
      max_eff: Keyword.fetch!(opts, :max_eff),
      peak_speed: Keyword.get(opts, :peak_speed, 1.5),
      sigma: Keyword.fetch!(opts, :sigma),
      demand_per_turbine: Keyword.fetch!(opts, :demand),
      total_power: 0.0, total_steam_produced: 0.0,
      total_steam_consumed: 0.0, total_steam_vented: 0.0,
      total_ticks_starved: 0, tick_count: 0,
      power_history: [], pressure_history: [],
      speed_histories: List.duplicate([], n_turb),
      temp_history: []
    }
  end

  defp advance_tick(temp, heating, pt, rate, pl, op, dang) do
    delta = if heating, do: rate, else: -rate
    t = max(temp + delta, 0.0)
    if pt >= pl - 1,
      do: {t, if(t >= dang, do: false, else: true), 0},
      else: {t, heating, pt + 1}
  end

  def simulate(st, duration) do
    Enum.reduce(1..duration, st, fn _, s -> s |> step_reactors() |> step_turbines() |> record()|> step_tick() end)
  end

  def step_reactors(st) do
    {new_reactors, total_steam} =
      Enum.map_reduce(st.reactors, 0.0, fn r, acc ->
        delta = if r.heating?, do: r.temp_rate, else: -r.temp_rate
        t = max(r.temperature + delta, 0.0)
        {t, h, p} = if r.phase_tick >= r.phase_length - 1,
          do: {t, if(t >= r.danger_temp, do: false, else: true), 0},
          else: {t, r.heating?, r.phase_tick + 1}
        steam = if t > r.operating_temp, do: (t - r.operating_temp) / 100.0, else: 0.0
        {%{r | temperature: t, heating?: h, phase_tick: p}, acc + steam}
      end)

    new_p = st.pressure + total_steam
    vented = max(new_p - st.capacity, 0.0)
    %{st | reactors: new_reactors, pressure: min(new_p, st.capacity),
           total_steam_produced: st.total_steam_produced + total_steam,
           total_steam_vented: st.total_steam_vented + vented}
  end

  def step_turbines(st) do
    n = length(st.turbine_speeds)
    if n == 0, do: st, else: do_step(st, n)
  end

  defp do_step(st, n) do
    total_demand = st.demand_per_turbine * n
    # How much can actually be supplied?
    actual_total = min(total_demand, st.pressure)
    actual_per = actual_total / n
    starved = if actual_total < total_demand * 0.99, do: 1, else: 0

    new_speeds = Enum.map(st.turbine_speeds, fn speed ->
      (speed + actual_per * st.accel) * (1 - st.friction)
    end)

    tick_power = Enum.map(new_speeds, fn speed ->
      eff = gaussian(speed, st.peak_speed, st.sigma)
      eff * st.max_eff * actual_per
    end) |> Enum.sum()

    %{st |
      turbine_speeds: new_speeds,
      pressure: max(st.pressure - actual_total, 0.0),
      total_power: st.total_power + tick_power,
      total_steam_consumed: st.total_steam_consumed + actual_total,
      total_ticks_starved: st.total_ticks_starved + starved
    }
  end

  def gaussian(s, p, sig), do: :math.exp(-:math.pow(s - p, 2) / (2 * sig * sig))

  def record(st) do
    new_sh = Enum.zip(st.speed_histories, st.turbine_speeds)
      |> Enum.map(fn {h, s} -> [s | h] end)
    avg_t = Enum.sum(Enum.map(st.reactors, & &1.temperature)) / max(length(st.reactors), 1)
    %{st | pressure_history: [st.pressure | st.pressure_history],
           temp_history: [avg_t | st.temp_history]}
    |> Map.put(:speed_histories, new_sh)
  end

  def step_tick(st), do: %{st | tick_count: st.tick_count + 1}

  def avg_power(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_power / st.tick_count)

  def speed_range(st) do
    settled = hd(st.speed_histories) |> Enum.reverse() |> Enum.drop(120)
    if settled == [], do: {0.0, 0.0}, else: {Enum.min(settled), Enum.max(settled)}
  end

  def pressure_range(st) do
    settled = st.pressure_history |> Enum.reverse() |> Enum.drop(120)
    if settled == [], do: {0.0, 0.0}, else: {Enum.min(settled), Enum.max(settled)}
  end

  def starved_pct(st), do: if(st.tick_count == 0, do: 0.0, else: st.total_ticks_starved / st.tick_count * 100)
end

# =============================================================================

IO.puts("=" |> String.duplicate(82))
IO.puts("  STEAM PRESSURE v3 — FIXED DEMAND, VARIABLE SUPPLY")
IO.puts("=" |> String.duplicate(82))
IO.puts("")
IO.puts("  Each turbine demands a FIXED amount of steam per tick.")
IO.puts("  If header pressure can't supply it, turbines are starved.")
IO.puts("  Buffering (tanks) and smoothing (offset reactors) help avoid starvation.")
IO.puts("")

peak = 1.5
accel = 1.0
duration = 480

bearing_tiers = [
  {"No bearings (base)", 0.10, 1.0, 0.40},
  {"Bronze Bearings",    0.07, 1.5, 0.55},
  {"Steel Bearings",     0.05, 2.0, 0.75},
  {"Titanium Bearings",  0.027, 3.0, 1.00}
]

# The demand per turbine should put the turbine at peak speed when fully fed.
# Terminal speed at demand d: d * accel * (1-f) / f = peak
# So d = peak * f / (accel * (1-f))
# For base: d = 1.5 * 0.1 / (1.0 * 0.9) = 0.1667
# This is exactly what the continuous model uses for 3 turbines at 0.5 steam total.
# But the demand should be fixed regardless of turbine count.

IO.puts("  Peak-speed demand per turbine by friction:")
Enum.each(bearing_tiers, fn {name, friction, _, _} ->
  d = peak * friction / (accel * (1 - friction))
  IO.puts("    #{String.pad_trailing(name, 22)} demand = #{Float.round(d, 4)}")
end)
IO.puts("")

# =============================================================================
# PART 1: Calibrate base_max_eff with demand model
# =============================================================================

IO.puts("== PART 1: CALIBRATING base_max_eff ==")
IO.puts("")
IO.puts("  With fixed demand, each turbine at peak gets exactly demand steam.")
IO.puts("  power_per_turb = 1.0 * max_eff * demand  (at peak, eff=100%)")
IO.puts("  For base: demand = 0.1667, want 80W/turb → max_eff = 80/0.1667 = 480")
IO.puts("  But with oscillation, turbines get less than demand during cold phases.")
IO.puts("  Need to find the max_eff that yields ~240W at 3 turbines under oscillation.")
IO.puts("")

base_demand = peak * 0.10 / (accel * 0.90)  # ≈ 0.1667

IO.puts("  Testing max_eff values (base, 3 turbines, demand=#{Float.round(base_demand, 4)}):")
IO.puts("")

Enum.each([480, 600, 720, 800, 900, 1000, 1200], fn me ->
  # At various capacities
  Enum.each([2.0, 10.0, 30.0], fn cap ->
    final = SteamSim.init(
      turbines: 3, friction: 0.10, max_eff: me * 1.0, sigma: 0.40,
      accel: accel, peak_speed: peak, capacity: cap,
      demand: base_demand,
      operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
    ) |> SteamSim.simulate(duration)

    pw = SteamSim.avg_power(final)
    starved = SteamSim.starved_pct(final)
    vented = if final.total_steam_produced > 0,
      do: final.total_steam_vented / final.total_steam_produced * 100, else: 0.0

    if cap == 2.0 do
      IO.puts(
        "  me=#{String.pad_leading("#{me}", 5)}" <>
        "  cap=2: #{String.pad_leading("#{Float.round(pw, 0)}", 5)}W starved=#{String.pad_leading("#{Float.round(starved, 0)}", 3)}% vent=#{Float.round(vented, 0)}%" <>
        "  |  cap=10: " <>
        (fn ->
          f2 = SteamSim.init(
            turbines: 3, friction: 0.10, max_eff: me * 1.0, sigma: 0.40,
            accel: accel, peak_speed: peak, capacity: 10.0,
            demand: base_demand,
            operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
          ) |> SteamSim.simulate(duration)
          "#{Float.round(SteamSim.avg_power(f2), 0)}W starved=#{Float.round(SteamSim.starved_pct(f2), 0)}%"
        end).() <>
        "  |  cap=30: " <>
        (fn ->
          f3 = SteamSim.init(
            turbines: 3, friction: 0.10, max_eff: me * 1.0, sigma: 0.40,
            accel: accel, peak_speed: peak, capacity: 30.0,
            demand: base_demand,
            operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
          ) |> SteamSim.simulate(duration)
          "#{Float.round(SteamSim.avg_power(f3), 0)}W starved=#{Float.round(SteamSim.starved_pct(f3), 0)}%"
        end).()
      )
    end
  end)
end)

IO.puts("")

# Use 480 as the continuous target is already right
# The question is: can buffering bring it close?
base_max_eff = 480.0

# =============================================================================
# PART 2: How many turbines fed by 1 reactor?
# =============================================================================

IO.puts("== PART 2: TURBINE COUNT (1 reactor, base bearings, max_eff=#{base_max_eff}) ==")
IO.puts("")
IO.puts("  demand/turb = #{Float.round(base_demand, 4)} (peak speed at full feed)")
IO.puts("  Avg steam = 0.5/tick from reactor")
IO.puts("  Max fed turbines = 0.5 / #{Float.round(base_demand, 4)} = #{Float.round(0.5 / base_demand, 1)}")
IO.puts("")

IO.puts("  N | demand | cap=2     | cap=10    | cap=30    | Continuous")
IO.puts("  " <> String.duplicate("-", 72))

Enum.each(1..8, fn n ->
  total_demand = base_demand * n

  results = Enum.map([2.0, 10.0, 30.0], fn cap ->
    final = SteamSim.init(
      turbines: n, friction: 0.10, max_eff: base_max_eff, sigma: 0.40,
      accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
      operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
    ) |> SteamSim.simulate(duration)
    {SteamSim.avg_power(final), SteamSim.starved_pct(final)}
  end)

  # Continuous reference
  se = min(0.5 / n, base_demand)  # can't get more than demand
  spd = se * accel * (1 - 0.10) / 0.10
  eff = SteamSim.gaussian(spd, peak, 0.40)
  cont = eff * base_max_eff * se * n

  IO.puts(
    "  #{String.pad_leading("#{n}", 2)} |" <>
    " #{String.pad_leading("#{Float.round(total_demand, 2)}", 6)} |" <>
    Enum.map_join(results, " |", fn {pw, st} ->
      " #{String.pad_leading("#{Float.round(pw, 0)}", 4)}W s=#{String.pad_leading("#{Float.round(st, 0)}", 2)}%"
    end) <>
    " | #{String.pad_leading("#{Float.round(cont, 0)}", 5)}W"
  )
end)

IO.puts("")

# =============================================================================
# PART 3: Buffer matters! Show how tanks help when turbines > 3
# =============================================================================

IO.puts("== PART 3: CAPACITY SWEEP AT 3 TURBINES (base, max_eff=#{base_max_eff}) ==")
IO.puts("")

caps = [1.0, 2.0, 3.0, 5.0, 8.0, 10.0, 15.0, 20.0, 30.0, 50.0]

IO.puts("  Cap | Power | Starved% | Vented% | Pressure Range | Speed Range")
IO.puts("  " <> String.duplicate("-", 72))

Enum.each(caps, fn cap ->
  final = SteamSim.init(
    turbines: 3, friction: 0.10, max_eff: base_max_eff, sigma: 0.40,
    accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration)

  pw = SteamSim.avg_power(final)
  st = SteamSim.starved_pct(final)
  vt = if final.total_steam_produced > 0,
    do: final.total_steam_vented / final.total_steam_produced * 100, else: 0.0
  {pmin, pmax} = SteamSim.pressure_range(final)
  {smin, smax} = SteamSim.speed_range(final)

  IO.puts(
    "  #{String.pad_leading("#{cap}", 4)} |" <>
    " #{String.pad_leading("#{Float.round(pw, 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(st, 0)}", 8)}% |" <>
    " #{String.pad_leading("#{Float.round(vt, 1)}", 7)}% |" <>
    " #{String.pad_leading("#{Float.round(pmin, 1)}", 5)}-#{String.pad_leading("#{Float.round(pmax, 1)}", 5)} |" <>
    " #{Float.round(smin, 2)}-#{Float.round(smax, 2)}"
  )
end)

IO.puts("")

# =============================================================================
# PART 4: Dual reactor phase-offset
# =============================================================================

IO.puts("== PART 4: DUAL REACTOR PHASE OFFSET ==")
IO.puts("")
IO.puts("  Two reactors feeding shared header, turbines = 6 (3 per reactor)")
IO.puts("  Offset = 60 ticks (half cycle) — when A heats, B cools")
IO.puts("")

configs = [
  {"1R, 3T, cap=2",        1, [0],     3, 2.0},
  {"1R, 3T, cap=10",       1, [0],     3, 10.0},
  {"1R, 3T, cap=30",       1, [0],     3, 30.0},
  {"2R, 6T, cap=2, no ofs", 2, [0, 0], 6, 2.0},
  {"2R, 6T, cap=2, ofs=60", 2, [0, 60], 6, 2.0},
  {"2R, 6T, cap=10, ofs=60",2, [0, 60], 6, 10.0},
  {"2R, 6T, cap=10, ofs=30",2, [0, 30], 6, 10.0},
  {"2R, 6T, cap=2, ofs=30", 2, [0, 30], 6, 2.0},
]

IO.puts("  Config                 | Power | /React | Starved | Spd Range | Press Range")
IO.puts("  " <> String.duplicate("-", 80))

Enum.each(configs, fn {label, nr, offsets, nt, cap} ->
  final = SteamSim.init(
    turbines: nt, reactors: nr, phase_offsets: offsets,
    friction: 0.10, max_eff: base_max_eff, sigma: 0.40,
    accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration)

  pw = SteamSim.avg_power(final)
  per_r = pw / nr
  st = SteamSim.starved_pct(final)
  {smin, smax} = SteamSim.speed_range(final)
  {pmin, pmax} = SteamSim.pressure_range(final)

  IO.puts(
    "  #{String.pad_trailing(label, 24)} |" <>
    " #{String.pad_leading("#{Float.round(pw, 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(per_r, 0)}", 5)}W |" <>
    " #{String.pad_leading("#{Float.round(st, 0)}", 7)}% |" <>
    " #{Float.round(smin, 2)}-#{Float.round(smax, 2)} |" <>
    " #{Float.round(pmin, 1)}-#{Float.round(pmax, 1)}"
  )
end)

IO.puts("")

# =============================================================================
# PART 5: FULL PROGRESSION WITH SKILL LEVELS
# =============================================================================

IO.puts("== PART 5: FULL BEARING PROGRESSION WITH SKILL LEVELS ==")
IO.puts("")
IO.puts("  Basic:  1 reactor, cap=2 (just reactor, no extras)")
IO.puts("  Tanks:  1 reactor, cap=15 (added pressure tanks)")
IO.puts("  Expert: 2 reactors offset, cap=15 (tanks + offset)")
IO.puts("  Cont:   theoretical continuous model")
IO.puts("")

IO.puts("  " <>
  String.pad_trailing("Tier", 22) <>
  String.pad_leading("N", 3) <>
  String.pad_leading("Basic", 8) <>
  String.pad_leading("Tanks", 8) <>
  String.pad_leading("Expert", 8) <>
  String.pad_leading("Cont", 8) <>
  String.pad_leading("B/C", 6) <>
  String.pad_leading("T/C", 6) <>
  String.pad_leading("E/C", 6)
)
IO.puts("  " <> String.duplicate("-", 75))

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult
  demand = peak * friction / (accel * (1 - friction))
  n = 3  # base turbine count per reactor

  # Continuous
  se = 0.5 / n
  spd = se * accel * (1 - friction) / friction
  eff = SteamSim.gaussian(spd, peak, sigma)
  cont = eff * max_eff * se * n

  # Basic
  basic = SteamSim.init(
    turbines: n, friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 2.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power()

  # Tanks
  tanks = SteamSim.init(
    turbines: n, friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power()

  # Expert (2 reactors, 2x turbines, offset)
  expert_total = SteamSim.init(
    turbines: n * 2, reactors: 2, phase_offsets: [0, 60],
    friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power()
  expert = expert_total / 2  # per reactor

  IO.puts("  " <>
    String.pad_trailing(name, 22) <>
    String.pad_leading("#{n}", 3) <>
    String.pad_leading("#{Float.round(basic, 0)}W", 8) <>
    String.pad_leading("#{Float.round(tanks, 0)}W", 8) <>
    String.pad_leading("#{Float.round(expert, 0)}W", 8) <>
    String.pad_leading("#{Float.round(cont, 0)}W", 8) <>
    String.pad_leading("#{Float.round(basic/cont*100, 0)}%", 6) <>
    String.pad_leading("#{Float.round(tanks/cont*100, 0)}%", 6) <>
    String.pad_leading("#{Float.round(expert/cont*100, 0)}%", 6)
  )
end)

IO.puts("")

# Also show with optimal turbine counts
IO.puts("  Now with pressure-optimal turbine counts:")
IO.puts("")

IO.puts("  " <>
  String.pad_trailing("Tier", 22) <>
  String.pad_leading("OptN", 5) <>
  String.pad_leading("Basic", 8) <>
  String.pad_leading("Tanks", 8) <>
  String.pad_leading("Expert", 8) <>
  String.pad_leading("B/C", 6) <>
  String.pad_leading("T/C", 6) <>
  String.pad_leading("E/C", 6)
)
IO.puts("  " <> String.duplicate("-", 69))

Enum.each(bearing_tiers, fn {name, friction, eff_mult, sigma} ->
  max_eff = base_max_eff * eff_mult
  demand = peak * friction / (accel * (1 - friction))

  # Continuous optimal
  {cont_n, cont_pw} = Enum.reduce(1..30, {1, 0.0}, fn n, {bn, bt} = acc ->
    se = min(0.5 / n, demand)
    spd = se * accel * (1 - friction) / friction
    eff = SteamSim.gaussian(spd, peak, sigma)
    tot = eff * max_eff * se * n
    if tot > bt, do: {n, tot}, else: acc
  end)

  # Find pressure-optimal at cap=15 (tanks)
  tank_results = Enum.map(1..20, fn n ->
    f = SteamSim.init(
      turbines: n, friction: friction, max_eff: max_eff, sigma: sigma,
      accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
      operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
    ) |> SteamSim.simulate(duration)
    {n, SteamSim.avg_power(f)}
  end)
  {opt_n, _} = Enum.max_by(tank_results, fn {_, p} -> p end)

  # Basic at opt_n
  basic = SteamSim.init(
    turbines: opt_n, friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 2.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power()

  # Tanks
  tanks = SteamSim.init(
    turbines: opt_n, friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power()

  # Expert
  expert = SteamSim.init(
    turbines: opt_n * 2, reactors: 2, phase_offsets: [0, 60],
    friction: friction, max_eff: max_eff, sigma: sigma,
    accel: accel, peak_speed: peak, capacity: 15.0, demand: demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(duration) |> SteamSim.avg_power() |> Kernel./(2)

  IO.puts("  " <>
    String.pad_trailing(name, 22) <>
    String.pad_leading("#{opt_n}", 5) <>
    String.pad_leading("#{Float.round(basic, 0)}W", 8) <>
    String.pad_leading("#{Float.round(tanks, 0)}W", 8) <>
    String.pad_leading("#{Float.round(expert, 0)}W", 8) <>
    String.pad_leading("#{Float.round(basic/cont_pw*100, 0)}%", 6) <>
    String.pad_leading("#{Float.round(tanks/cont_pw*100, 0)}%", 6) <>
    String.pad_leading("#{Float.round(expert/cont_pw*100, 0)}%", 6)
  )
end)

IO.puts("")

# =============================================================================
# PART 6: TICK DETAIL — show starvation dynamics
# =============================================================================

IO.puts("== PART 6: TICK DETAIL (base, 3 turbs, cap=2 vs cap=15) ==")
IO.puts("")

Enum.each([{2.0, "cap=2 (basic)"}, {15.0, "cap=15 (tanks)"}], fn {cap, label} ->
  IO.puts("  #{label}:")

  final = SteamSim.init(
    turbines: 3, friction: 0.10, max_eff: base_max_eff, sigma: 0.40,
    accel: accel, peak_speed: peak, capacity: cap, demand: base_demand,
    operating_temp: 100.0, danger_temp: 200.0, temp_rate: 1.667, phase_length: 60
  ) |> SteamSim.simulate(240)

  temps = Enum.reverse(final.temp_history)
  pressures = Enum.reverse(final.pressure_history)
  speeds = hd(final.speed_histories) |> Enum.reverse()

  IO.puts("  Tick | Temp   | Steam | Pressure | Speed  | Fed?")
  IO.puts("  " <> String.duplicate("-", 55))

  Enum.each(0..23, fn i ->
    t = i * 10
    if t < length(temps) do
      temp = Enum.at(temps, t)
      press = Enum.at(pressures, t)
      spd = Enum.at(speeds, t)
      sr = if temp > 100, do: (temp - 100) / 100, else: 0.0
      total_d = base_demand * 3
      fed = if press + sr >= total_d, do: "YES", else: "NO "

      IO.puts(
        "  #{String.pad_leading("#{t}", 4)} |" <>
        " #{String.pad_leading("#{Float.round(temp, 1)}", 6)} |" <>
        " #{String.pad_leading("#{Float.round(sr, 3)}", 5)} |" <>
        " #{String.pad_leading("#{Float.round(press, 2)}", 8)} |" <>
        " #{String.pad_leading("#{Float.round(spd, 3)}", 6)} |" <>
        "  #{fed}"
      )
    end
  end)

  IO.puts("  Avg power: #{Float.round(SteamSim.avg_power(final), 0)}W, starved: #{Float.round(SteamSim.starved_pct(final), 0)}%")
  IO.puts("")
end)

# =============================================================================
IO.puts("=" |> String.duplicate(82))
IO.puts("  CONCLUSIONS")
IO.puts("=" |> String.duplicate(82))
IO.puts("")
IO.puts("  With fixed demand per turbine:")
IO.puts("  - Turbines request a constant steam rate (tuned to reach peak speed)")
IO.puts("  - Header pressure determines if demand can be met")
IO.puts("  - During cold phases, supply < demand → turbines starve → speed drops")
IO.puts("  - Pressure tanks buffer hot-phase surplus for cold-phase use")
IO.puts("  - Phase-offset dual reactors maintain steadier combined supply")
IO.puts("")
IO.puts("  Player optimization ladder:")
IO.puts("  1. Basic reactor + turbines (just works, ~X% efficient)")
IO.puts("  2. Add pressure tanks (buffer smoothing, ~Y% efficient)")
IO.puts("  3. Dual reactor with phase offset (near-continuous, ~Z% efficient)")
IO.puts("  4. Bearing upgrades unlock higher power ceiling at each level")
IO.puts("")
