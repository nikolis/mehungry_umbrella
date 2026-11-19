defmodule Mehungry.Professionals.ClientMealContext do
  @moduledoc """
  The single source of truth for the client brief an AI meal-plan draft is
  tailored to, when a **nutritionist** drafts for a client.

  It merges two sources that hold the same concepts — the client's own
  `Accounts.UserProfile` (diet, calorie target, personal avoid list, lactose)
  and the nutritionist-owned file (`ProfessionalClient` → `ClientIntake` for
  goal/anthropometrics/TDEE/allergies, `ClientCondition` for linked conditions,
  `ConsultationNote` for the latest note) — with one firm rule:

  > Where both sides hold a value for an overlapping field, the **nutritionist's**
  > value is surfaced over the client's self-entered value.

  Concretely: the clinician's `tdee_kcal` wins over the client's profile calorie
  target, and the foods-to-avoid list unions the client's personal avoid list
  with the nutritionist's intake allergy/intolerance/aversion terms and
  condition-implicated foods. `diet` and `lactose_intolerant` have no
  nutritionist-side field today, so they stay client-sourced (there is nothing
  on the nutritionist's end to prefer).

  `NutritionistMealPlanAgent` resolves it once per run: it is what the
  `get_client_record` tool returns and what the agent's deterministic diet /
  avoid guards are built from, so the precedence is defined once and cannot drift.
  """

  alias Mehungry.{Accounts, Health, Professionals}

  @doc """
  Resolve the merged, precedence-applied client brief for `client_id` as seen by
  `professional_id`. Returns a map:

      %{
        has_record: boolean,
        diet: "omnivore" | "vegetarian" | ...,   # client profile (no nutritionist field)
        lactose_intolerant: boolean,             # client profile
        calorie_target: integer | nil,           # intake.tdee_kcal wins, else profile target
        goal: String.t() | nil,                  # intake
        conditions: [String.t()],                # ClientCondition names
        avoid: [String.t()],                     # profile avoid ∪ intake terms ∪ condition foods
        avoid_free_text: [String.t()],           # the subset of `avoid` typed as intake free text
        avoid_ingredient_ids: [integer],         # exact ingredient ids implicated by the conditions
        anthropometrics: map | nil,              # intake
        latest_note: %{body: _, todo: _} | nil   # latest ConsultationNote
      }
  """
  def resolve(professional_id, client_id) do
    record = Professionals.get_client_record_by_user(professional_id, client_id)
    profile = Accounts.get_user_profile_by_user_id(client_id)
    intake = record && Professionals.get_latest_intake(record.id)
    conditions = if record, do: Professionals.list_client_conditions(record.id), else: []

    latest_note =
      record && record.id |> Professionals.list_consultation_notes() |> List.last()

    # Condition-implicated foods, resolved once: their names feed the prompt-facing
    # `avoid` list, their ids feed the planner's exact (composition-aware) filter —
    # a USDA name like "Spinach, raw" never matches a recipe title by substring.
    condition_avoid =
      Enum.flat_map(conditions, fn c -> Health.ingredients_for_condition(c.id, "avoid") end)

    %{
      has_record: not is_nil(record),
      diet: profile_diet(profile),
      lactose_intolerant: profile_lactose(profile),
      calorie_target: calorie_target(intake, profile),
      goal: intake && intake.goal,
      conditions: Enum.map(conditions, & &1.name),
      avoid: avoid_list(profile, intake, condition_avoid),
      # Free text is too loose to enforce like a curated list (a stray "no" or
      # "oil" would match half the catalog), so the planner treats it separately.
      avoid_free_text: free_text_only(profile, intake, condition_avoid),
      avoid_ingredient_ids: condition_avoid |> Enum.map(& &1.ingredient.id) |> Enum.uniq(),
      anthropometrics: anthropometrics_summary(intake),
      latest_note: latest_note && %{body: latest_note.body, todo: latest_note.todo}
    }
  end

  # Diet/lactose have no nutritionist-side field, so they are read straight from
  # the client's own profile (with the schema defaults when there is no profile).
  defp profile_diet(%{diet: diet}) when is_binary(diet), do: diet
  defp profile_diet(_), do: "omnivore"

  defp profile_lactose(%{lactose_intolerant: lactose}) when is_boolean(lactose), do: lactose
  defp profile_lactose(_), do: false

  # Daily calorie target: the intake's TDEE wins (clinician-assessed), else the
  # client's own profile target, else nil.
  defp calorie_target(intake, profile) do
    cond do
      intake && intake.tdee_kcal -> intake.tdee_kcal
      profile && profile.daily_calorie_target -> profile.daily_calorie_target
      true -> nil
    end
  end

  # Unified list of foods to never use: the client's personal avoid list + intake
  # allergy/intolerance terms + condition-implicated foods resolved through the same
  # curated Health engine the /foods filter uses (condition → "avoid" compound
  # recommendations → species → ingredients). Deduped + capped.
  defp avoid_list(profile, intake, condition_avoid) do
    condition_names = Enum.map(condition_avoid, & &1.ingredient.name)

    [(profile && profile.avoid_foods) || [], intake_avoid_terms(intake), condition_names]
    |> List.flatten()
    |> Enum.map(&String.trim(to_string(&1)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(40)
  end

  # Intake free-text terms that are not also on a curated list (the client's
  # avoid chips, a condition's foods) — a term confirmed there keeps its
  # stricter handling.
  defp free_text_only(profile, intake, condition_avoid) do
    curated =
      [(profile && profile.avoid_foods) || [], Enum.map(condition_avoid, & &1.ingredient.name)]
      |> List.flatten()
      |> MapSet.new(&(&1 |> to_string() |> String.trim() |> String.downcase()))

    intake
    |> intake_avoid_terms()
    |> Enum.map(&String.trim(to_string(&1)))
    |> Enum.reject(&(&1 == "" or MapSet.member?(curated, String.downcase(&1))))
    |> Enum.uniq()
  end

  defp anthropometrics_summary(nil), do: nil

  defp anthropometrics_summary(intake) do
    %{
      weight_kg: intake.weight_kg,
      bmi: intake.bmi,
      sex: intake.sex,
      age: intake.age,
      activity_level: intake.activity_level,
      tdee_kcal: intake.tdee_kcal,
      bmr_kcal: intake.bmr_kcal
    }
  end

  # Avoid terms from a client intake's free-form `details` JSONB (allergies,
  # intolerances, aversions). Each value may be a list or a comma/newline-separated
  # string; both are flattened into discrete terms.
  defp intake_avoid_terms(%{details: details}) when is_map(details) do
    ~w(allergies food_intolerances food_aversions)
    |> Enum.flat_map(fn key -> details |> Map.get(key) |> split_terms() end)
  end

  defp intake_avoid_terms(_), do: []

  defp split_terms(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp split_terms(value) when is_binary(value), do: String.split(value, ~r/[,;\n]/, trim: true)
  defp split_terms(_), do: []
end
