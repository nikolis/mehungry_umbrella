defmodule MehungryWeb.DietaryHistory.Labels do
  @moduledoc """
  Localized labels for the dietary-history questionnaire and 24-hour recall.

  `Mehungry.Professionals.DietaryHistory.Fields` (in the core app) is the single
  source of the `details` keys and their display order, returning stable English
  labels. Those labels were rendered verbatim, so the Questionnaire / 24-hour
  recall sections stayed English even in `el`. This web-side module provides the
  gettext translation for each label via the `gettext/1` macro (literals, so
  `mix gettext.extract` keeps them in the catalog). The client views translate
  through `translate/1` at render time.
  """
  use Gettext, backend: MehungryWeb.Gettext

  @doc """
  Translate a questionnaire / 24-hour-recall label (the English label as it
  comes from `Fields`) into the request locale. Unknown labels pass through
  unchanged, so a future field added to `Fields` degrades to English rather than
  crashing until its translation is added here.
  """
  # Questionnaire (`details`) labels.
  def translate("Reason for visit"), do: gettext("Reason for visit")
  def translate("Marital status"), do: gettext("Marital status")
  def translate("Weight fluctuations"), do: gettext("Weight fluctuations")
  def translate("Milestone events"), do: gettext("Milestone events")
  def translate("Past attempts"), do: gettext("Past attempts")
  def translate("Family weight history"), do: gettext("Family weight history")
  def translate("Hereditary conditions"), do: gettext("Hereditary conditions")
  def translate("GI function"), do: gettext("GI function")
  def translate("Medications"), do: gettext("Medications")
  def translate("Blood biochemistry"), do: gettext("Blood biochemistry")
  def translate("Thyroid tests"), do: gettext("Thyroid tests")
  def translate("Gynecological history"), do: gettext("Gynecological history")
  def translate("Allergies"), do: gettext("Allergies")
  def translate("Alcohol"), do: gettext("Alcohol")
  def translate("Fluids"), do: gettext("Fluids")
  def translate("Smoking"), do: gettext("Smoking")
  def translate("Sleep"), do: gettext("Sleep")
  def translate("Physical activity"), do: gettext("Physical activity")
  def translate("Food intolerances"), do: gettext("Food intolerances")
  def translate("Food aversions"), do: gettext("Food aversions")
  def translate("Special eating habits"), do: gettext("Special eating habits")
  def translate("Unconscious eating"), do: gettext("Unconscious eating")
  def translate("Emotional overeating"), do: gettext("Emotional overeating")
  def translate("Overconsumption"), do: gettext("Overconsumption")
  def translate("Expectations assessment"), do: gettext("Expectations assessment")
  def translate("Reason justification"), do: gettext("Reason justification")
  def translate("Observations"), do: gettext("Observations")
  def translate("Notes"), do: gettext("Notes")

  # 24-hour recall labels.
  def translate("Breakfast"), do: gettext("Breakfast")
  def translate("Mid-morning"), do: gettext("Mid-morning")
  def translate("Lunch"), do: gettext("Lunch")
  def translate("Afternoon"), do: gettext("Afternoon")
  def translate("Dinner"), do: gettext("Dinner")
  def translate("Vegetable intake"), do: gettext("Vegetable intake")
  def translate("Fruit intake"), do: gettext("Fruit intake")

  def translate(other) when is_binary(other), do: other
end
