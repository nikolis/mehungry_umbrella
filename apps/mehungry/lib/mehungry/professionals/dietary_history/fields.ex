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
  # `{key, English label, Greek label}`, in display order. Greek is used to seed
  # the bilingual `Onboarding` `"client_default"` template (so the client
  # onboarding questionnaire renders in `el`); the `detail_labels/0` /
  # `recall_labels/0` accessors return just `{key, English}` for callers that
  # localize separately (the nutritionist client-file view translates via
  # `MehungryWeb.DietaryHistory.Labels`, whose `el/default.po` entries mirror the
  # Greek here — keep the two in sync).
  #
  # NB: `age` is intentionally NOT here — it is a structured `ClientIntake.age`
  # column (shown in the intake metrics and used for BMR/TDEE), so listing it as
  # a questionnaire detail rendered it twice in the client view.
  @detail_labels [
    {"reason_for_visit", "Reason for visit", "Αιτία προσέλευσης"},
    {"marital_status", "Marital status", "Οικογενειακή κατάσταση"},
    {"weight_fluctuations", "Weight fluctuations", "Διακυμάνσεις βάρους"},
    {"milestone_events", "Milestone events", "Γεγονότα-σταθμοί"},
    {"past_attempts", "Past attempts", "Προηγούμενες προσπάθειες"},
    {"family_weight_history", "Family weight history", "Οικογενειακό ιστορικό βάρους"},
    {"hereditary_conditions", "Hereditary conditions", "Κληρονομικά νοσήματα"},
    {"gi_function", "GI function", "Γαστρεντερική λειτουργία"},
    {"medications", "Medications", "Φάρμακα"},
    {"blood_biochem", "Blood biochemistry", "Βιοχημική αίματος"},
    {"thyroid_tests", "Thyroid tests", "Εξετάσεις θυρεοειδούς"},
    {"gynecological_history", "Gynecological history", "Γυναικολογικό ιστορικό"},
    {"allergies", "Allergies", "Αλλεργίες"},
    {"alcohol", "Alcohol", "Αλκοόλ"},
    {"fluids", "Fluids", "Υγρά"},
    {"smoking", "Smoking", "Κάπνισμα"},
    {"sleep", "Sleep", "Ύπνος"},
    {"physical_activity", "Physical activity", "Φυσική δραστηριότητα"},
    {"food_intolerances", "Food intolerances", "Τροφικές δυσανεξίες"},
    {"food_aversions", "Food aversions", "Τροφικές απέχθειες"},
    {"special_eating_habits", "Special eating habits", "Ιδιαίτερες διατροφικές συνήθειες"},
    {"unconscious_eating", "Unconscious eating", "Ασυνείδητη κατανάλωση"},
    {"emotional_overeating", "Emotional overeating", "Συναισθηματική υπερφαγία"},
    {"overconsumption", "Overconsumption", "Υπερκατανάλωση"},
    {"expectations_assessment", "Expectations assessment", "Αξιολόγηση προσδοκιών"},
    {"reason_justification", "Reason justification", "Αιτιολόγηση προσέλευσης"},
    {"observations", "Observations", "Παρατηρήσεις"},
    {"notes", "Notes", "Σημειώσεις"}
  ]

  # `details["recall_24h"][<key>]` fields → `{key, English, Greek}`, display order.
  @recall_labels [
    {"breakfast", "Breakfast", "Πρωινό"},
    {"mid_morning", "Mid-morning", "Δεκατιανό"},
    {"lunch", "Lunch", "Μεσημεριανό"},
    {"afternoon", "Afternoon", "Απογευματινό"},
    {"dinner", "Dinner", "Βραδινό"},
    {"vegetable_intake", "Vegetable intake", "Κατανάλωση λαχανικών"},
    {"fruit_intake", "Fruit intake", "Κατανάλωση φρούτων"}
  ]

  @doc "Questionnaire `details` keys with English labels, in display order."
  def detail_labels, do: Enum.map(@detail_labels, fn {k, en, _el} -> {k, en} end)

  @doc "24-hour recall keys with English labels, in display order."
  def recall_labels, do: Enum.map(@recall_labels, fn {k, en, _el} -> {k, en} end)

  @doc "Full `{key, English, Greek}` questionnaire entries (for bilingual seeding)."
  def detail_entries, do: @detail_labels

  @doc "Full `{key, English, Greek}` 24-hour-recall entries."
  def recall_entries, do: @recall_labels
end
