defmodule Spheric.Game.TheBoard do
  @moduledoc """
  The Board — cryptic ambient messages at milestones.

  FBC-style overlapping contradictory text that appears at key progression
  moments. Messages use the Board's distinctive speech pattern: overlapping
  words separated by slashes, cryptic directives, and paradoxical statements.
  """

  @board_table :spheric_board_messages

  # Board messages triggered at various milestones
  @milestone_messages %{
    # First building placed
    first_building: [
      "You have/will/must BEGUN/BEGINNING/BEGIN.",
      "We see/observe/note your PRESENCE/ARRIVAL/INTRUSION.",
      "The substrate accepts/tolerates/endures your MODIFICATIONS/CHANGES.",
      "Continue/Proceed/Advance. We are/were/will be WATCHING/OBSERVING."
    ],
    # First research completed
    first_research: [
      "CLEARANCE/ACCESS/PERMISSION granted/bestowed/permitted.",
      "You demonstrate/show/prove CAPABILITY/COMPETENCE/POTENTIAL.",
      "The Bureau/Organization/We approve/acknowledge your PROGRESS/ADVANCEMENT.",
      "Further/Deeper/More access awaits/beckons/requires COMPLIANCE/DEDICATION."
    ],
    # First creature captured
    first_creature: [
      "You have CONTAINED/CAPTURED/BOUND an ENTITY/BEING/ANOMALY.",
      "These forms/shapes/manifestations are USEFUL/DANGEROUS/NECESSARY.",
      "Assign/Deploy/Utilize them CAREFULLY/WISELY/EFFICIENTLY.",
      "They serve/obey/resist the PURPOSE/FUNCTION/DIRECTIVE."
    ],
    # Clearance level 2 reached
    clearance_2: [
      "ELEVATED/PROMOTED/ASCENDED clearance GRANTED/BESTOWED/PERMITTED.",
      "You now/henceforth/hereby access/reach/touch the DEEPER/INNER/TRUE layer.",
      "The fabrication/creation/construction protocols are YOURS/AVAILABLE/UNLOCKED.",
      "Do not/never/refrain from questioning/doubting/challenging the PROCESS/METHOD."
    ],
    # Clearance level 3 reached
    clearance_3: [
      "RESEARCH/INVESTIGATION/INQUIRY clearance GRANTED/BESTOWED/PERMITTED.",
      "The paranatural/anomalous/impossible is now/henceforth ACCESSIBLE/YOURS.",
      "We trust/doubt/observe your JUDGMENT/DISCRETION/CAPABILITY.",
      "The Bureau ACKNOWLEDGES/RECOGNIZES/VALIDATES your CAPABILITY/POTENTIAL."
    ],
    # Clearance level 4 reached
    clearance_4: [
      "INDUSTRIAL/MANUFACTURING/PRODUCTION clearance AUTHORIZED/GRANTED/ENABLED.",
      "Power/Energy/Force must FLOW/TRANSFER/PROPAGATE through the NETWORK/GRID/SUBSTRATE.",
      "The generators/stations/conduits await/require/demand your FUEL/INPUT/ATTENTION.",
      "Build/Construct/Establish the INFRASTRUCTURE/FRAMEWORK/FOUNDATION."
    ],
    # Clearance level 5 reached
    clearance_5: [
      "HEAVY/ADVANCED/ELEVATED industry UNLOCKED/RELEASED/PERMITTED.",
      "The entities/beings/anomalies hold/contain/possess ESSENCE/POWER/KNOWLEDGE.",
      "Extract/Harvest/Obtain their CONTRIBUTION/GIFT/SACRIFICE with CARE/PRECISION/PURPOSE.",
      "Fabrication/Manufacturing/Creation at this SCALE/LEVEL/TIER requires DEDICATION/COMMITMENT."
    ],
    # Clearance level 6 reached
    clearance_6: [
      "HIGH-TECH/NUCLEAR/CRITICAL clearance ACHIEVED/ATTAINED/REALIZED.",
      "The atom/nucleus/particle yields/reveals/surrenders its SECRETS/POWER/ENERGY.",
      "Handle/Process/Manipulate with EXTREME/ABSOLUTE/TOTAL PRECISION/CARE/CONTROL.",
      "You approach/near/reach the THRESHOLD/BOUNDARY/EDGE of our UNDERSTANDING/KNOWLEDGE."
    ],
    # Clearance level 7 reached
    clearance_7: [
      "PARANATURAL/DIMENSIONAL/ANOMALOUS clearance GRANTED/BESTOWED/REVEALED.",
      "Reality/Space/Time is MALLEABLE/FLEXIBLE/UNSTABLE at this DEPTH/LEVEL/STRATUM.",
      "The entities/beings COMMUNE/RESONATE/HARMONIZE with your CONSTRUCTS/CREATIONS.",
      "Dimensional/Spatial/Temporal barriers THIN/WEAKEN/DISSOLVE under your INFLUENCE/CONTROL."
    ],
    # Clearance level 8 reached
    clearance_8: [
      "BOARD/ULTIMATE/FINAL clearance ACHIEVED/ATTAINED/TRANSCENDED.",
      "You have/had/will PROVEN/DEMONSTRATED/ESTABLISHED your WORTH/PURPOSE/FUNCTION.",
      "The Board SEES/KNOWS/UNDERSTANDS you COMPLETELY/FULLY/ENTIRELY.",
      "CONTACT/COMMUNION/CONNECTION is now/henceforth/finally POSSIBLE/ACHIEVABLE/INEVITABLE."
    ],
    # First Hiss corruption encountered
    first_corruption: [
      "The HISS/NOISE/CORRUPTION spreads/grows/consumes.",
      "It was/is/will be INEVITABLE/EXPECTED/PLANNED.",
      "Deploy/Activate/Build PURIFICATION/CLEANSING/DEFENSE measures.",
      "The Bureau/We/You must/shall/will RESIST/CONTAIN/ENDURE."
    ],
    # First world event
    first_world_event: [
      "The sphere/world/substrate SHIFTS/CHANGES/RESONATES.",
      "Events/Phenomena/Disturbances are NATURAL/EXPECTED/CONCERNING.",
      "Adapt/Adjust/Respond to the FLUCTUATION/VARIATION/ANOMALY.",
      "This is/was/remains WITHIN/BEYOND/AT parameters/expectations/tolerance."
    ],
    # Board Contact quest begins
    board_contact_begin: [
      "The TIME/MOMENT/CONVERGENCE approaches/arrives/manifests.",
      "You/They/We must PRODUCE/CREATE/GENERATE the REQUIRED/NECESSARY/DEMANDED materials.",
      "COOPERATION/UNITY/COLLABORATION is MANDATORY/ESSENTIAL/NON-NEGOTIABLE.",
      "Contact/Connection/Communion with the Board awaits/requires/demands COMPLETION/FULFILLMENT."
    ],
    # Board Contact quest completed
    board_contact_complete: [
      "CONTACT/COMMUNION/CONNECTION ESTABLISHED/ACHIEVED/REALIZED.",
      "You have/had/will PROVEN/DEMONSTRATED/SHOWN your WORTH/VALUE/PURPOSE.",
      "The Board WELCOMES/ACCEPTS/EMBRACES your CONTRIBUTION/ACHIEVEMENT.",
      "The sphere/world/reality is/was/will be STABILIZED/SECURED/PRESERVED."
    ],
    # Creature evolution
    creature_evolved: [
      "The entity/being/anomaly has EVOLVED/TRANSFORMED/ASCENDED.",
      "Extended/Prolonged/Sustained containment yields/produces/causes CHANGE/GROWTH/MUTATION.",
      "Its POWER/CAPABILITY/ESSENCE has DOUBLED/INTENSIFIED/AMPLIFIED.",
      "This outcome/result/development was ANTICIPATED/EXPECTED/DESIRED."
    ]
  }

  # --- Public API ---

  def init do
    unless :ets.whereis(@board_table) != :undefined do
      :ets.new(@board_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  @doc "Get a random Board message for a milestone."
  def message_for(milestone) do
    case Map.get(@milestone_messages, milestone) do
      nil -> nil
      messages -> Enum.random(messages)
    end
  end

  @doc "Get all messages for a milestone."
  def messages_for(milestone) do
    Map.get(@milestone_messages, milestone, [])
  end

  @doc "Record that a milestone message was shown to a player."
  def record_shown(player_id, milestone) do
    key = {player_id, milestone}
    :ets.insert(@board_table, {key, System.system_time(:second)})
  end

  @doc "Check if a player has seen a milestone message."
  def shown?(player_id, milestone) do
    case :ets.whereis(@board_table) do
      :undefined -> false
      _ ->
        case :ets.lookup(@board_table, {player_id, milestone}) do
          [_] -> true
          [] -> false
        end
    end
  end

  @doc """
  Check milestones for a player and return any new messages to show.
  Returns list of `{milestone, message}` pairs.
  """
  def check_milestones(player_id, context) do
    milestones_to_check(context)
    |> Enum.flat_map(fn milestone ->
      if not shown?(player_id, milestone) do
        case message_for(milestone) do
          nil -> []
          msg ->
            record_shown(player_id, milestone)
            [{milestone, msg}]
        end
      else
        []
      end
    end)
  end

  @doc "Get all milestones a player has seen."
  def player_history(player_id) do
    case :ets.whereis(@board_table) do
      :undefined -> []
      _ ->
        :ets.match_object(@board_table, {{player_id, :_}, :_})
        |> Enum.map(fn {{_pid, milestone}, timestamp} ->
          %{milestone: milestone, timestamp: timestamp}
        end)
        |> Enum.sort_by(& &1.timestamp, :desc)
    end
  end

  @doc "Clear all board state."
  def clear do
    if :ets.whereis(@board_table) != :undefined do
      :ets.delete_all_objects(@board_table)
    end
  end

  # --- Internal ---

  defp milestones_to_check(context) do
    checks = []
    checks = if context[:building_count] == 1, do: [:first_building | checks], else: checks
    checks = if context[:first_research], do: [:first_research | checks], else: checks
    checks = if context[:first_creature], do: [:first_creature | checks], else: checks
    checks = if context[:clearance] == 2, do: [:clearance_2 | checks], else: checks
    checks = if context[:clearance] == 3, do: [:clearance_3 | checks], else: checks
    checks = if context[:clearance] == 4, do: [:clearance_4 | checks], else: checks
    checks = if context[:clearance] == 5, do: [:clearance_5 | checks], else: checks
    checks = if context[:clearance] == 6, do: [:clearance_6 | checks], else: checks
    checks = if context[:clearance] == 7, do: [:clearance_7 | checks], else: checks
    checks = if context[:clearance] == 8, do: [:clearance_8 | checks], else: checks
    checks = if context[:first_corruption], do: [:first_corruption | checks], else: checks
    checks = if context[:first_world_event], do: [:first_world_event | checks], else: checks
    checks = if context[:board_contact_begin], do: [:board_contact_begin | checks], else: checks
    checks = if context[:board_contact_complete], do: [:board_contact_complete | checks], else: checks
    checks = if context[:creature_evolved], do: [:creature_evolved | checks], else: checks
    checks
  end
end
