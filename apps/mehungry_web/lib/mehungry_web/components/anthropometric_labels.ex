defmodule MehungryWeb.AnthropometricLabels do
  @moduledoc """
  Localized display labels for `Mehungry.Professionals.Anthropometrics` values
  (sex + activity level).

  The core app carries the canonical values and their English labels but has no
  Gettext backend, so — like `MehungryWeb.NutrientLabels` — this is the web-side
  chokepoint every render surface routes through: the client-file summary strip
  and intake form selects (`ClientDetailComponents`) and the read-only record
  view (`ClientRecord`).
  One `gettext/1` clause per canonical label so `mix gettext.extract` discovers
  them; unknown labels fall through unchanged.
  """
  use Gettext, backend: MehungryWeb.Gettext

  alias Mehungry.Professionals.Anthropometrics

  @doc "Localized display label for a stored `sex` value (`nil` → `nil`)."
  def sex_label(sex), do: translate(Anthropometrics.sex_label(sex))

  @doc "Localized display label for a stored `activity_level` value (`nil` → `nil`)."
  def activity_label(level), do: translate(Anthropometrics.activity_label(level))

  @doc "`{localized label, value}` select options for the sex pickers."
  def sex_options do
    for {value, label} <- Anthropometrics.sexes(), do: {translate(label), value}
  end

  @doc "`{localized label, value}` select options for the activity-level pickers."
  def activity_options do
    for {value, label, _factor} <- Anthropometrics.activity_levels(),
        do: {translate(label), value}
  end

  defp translate(nil), do: nil
  defp translate("Male"), do: gettext("Male")
  defp translate("Female"), do: gettext("Female")
  defp translate("Sedentary (little/no exercise)"), do: gettext("Sedentary (little/no exercise)")
  defp translate("Lightly active (1–3 days/wk)"), do: gettext("Lightly active (1–3 days/wk)")

  defp translate("Moderately active (3–5 days/wk)"),
    do: gettext("Moderately active (3–5 days/wk)")

  defp translate("Active (6–7 days/wk)"), do: gettext("Active (6–7 days/wk)")

  defp translate("Very active (hard exercise/physical job)"),
    do: gettext("Very active (hard exercise/physical job)")

  defp translate(other), do: other
end
