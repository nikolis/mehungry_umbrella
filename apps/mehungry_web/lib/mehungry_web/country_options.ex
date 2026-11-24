defmodule MehungryWeb.CountryOptions do
  @moduledoc """
  The "Where do you live?" country picker shared by the profile edit form and the
  onboarding wizard. The choices come from core's
  `Mehungry.Food.SeasonalAvailability.supported_countries/0` (the countries we have
  seasonal data for); names are localized here.
  """

  use Gettext, backend: MehungryWeb.Gettext

  @doc "`{label, code}` pairs for a `<.input type=\"select\">`."
  def options do
    Mehungry.Food.SeasonalAvailability.supported_countries()
    |> Enum.map(fn %{code: code, name: name} -> {label(code, name), code} end)
  end

  @doc "Why we ask — shown under the picker."
  def explanation do
    gettext(
      "We use your country only to suggest fruit that is in season where you live when we plan your meals. It is never shown on your public profile."
    )
  end

  # Literal msgids so `mix gettext.extract` picks the names up.
  defp label("GR", _), do: gettext("Greece")
  defp label("CY", _), do: gettext("Cyprus")
  defp label("IT", _), do: gettext("Italy")
  defp label("ES", _), do: gettext("Spain")
  defp label("DE", _), do: gettext("Germany")
  defp label(_code, name), do: name
end
