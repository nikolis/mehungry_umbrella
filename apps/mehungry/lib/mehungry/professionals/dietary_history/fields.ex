defmodule Mehungry.Professionals.DietaryHistory.Fields do
  @moduledoc """
  Single source of truth for the free-form `ClientIntake.details` keys and their
  human labels, in display order.

  Both the read-only record view (`MehungryWeb.NutritionistLive.ClientRecord`) and
  the manual editor (`MehungryWeb.NutritionistLive.ClientRecordEditor`) render
  from these lists, and the keys line up with what `DietaryHistory.CsvParser`
  routes into `details` / `details["recall_24h"]`, so an imported record and a
  hand-authored one carry the same shape.
  """

  # `details[<key>]` questionnaire fields → label, in display order.
  @detail_labels [
    {"reason_for_visit", "Reason for visit"},
    {"age", "Age"},
    {"marital_status", "Marital status"},
    {"weight_fluctuations", "Weight fluctuations"},
    {"milestone_events", "Milestone events"},
    {"past_attempts", "Past attempts"},
    {"family_weight_history", "Family weight history"},
    {"hereditary_conditions", "Hereditary conditions"},
    {"gi_function", "GI function"},
    {"medications", "Medications"},
    {"blood_biochem", "Blood biochemistry"},
    {"thyroid_tests", "Thyroid tests"},
    {"gynecological_history", "Gynecological history"},
    {"allergies", "Allergies"},
    {"alcohol", "Alcohol"},
    {"fluids", "Fluids"},
    {"smoking", "Smoking"},
    {"sleep", "Sleep"},
    {"physical_activity", "Physical activity"},
    {"food_intolerances", "Food intolerances"},
    {"food_aversions", "Food aversions"},
    {"special_eating_habits", "Special eating habits"},
    {"unconscious_eating", "Unconscious eating"},
    {"emotional_overeating", "Emotional overeating"},
    {"overconsumption", "Overconsumption"},
    {"expectations_assessment", "Expectations assessment"},
    {"reason_justification", "Reason justification"},
    {"observations", "Observations"},
    {"notes", "Notes"}
  ]

  # `details["recall_24h"][<key>]` fields → label, in display order.
  @recall_labels [
    {"breakfast", "Breakfast"},
    {"mid_morning", "Mid-morning"},
    {"lunch", "Lunch"},
    {"afternoon", "Afternoon"},
    {"dinner", "Dinner"},
    {"vegetable_intake", "Vegetable intake"},
    {"fruit_intake", "Fruit intake"}
  ]

  @doc "Questionnaire `details` keys with labels, in display order."
  def detail_labels, do: @detail_labels

  @doc "24-hour recall keys (under `details[\"recall_24h\"]`) with labels, in display order."
  def recall_labels, do: @recall_labels
end
