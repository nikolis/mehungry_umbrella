defmodule Mehungry.AI.Eval.EvalSeasons do
  @moduledoc """
  Seasonal availability for the meal-plan eval catalog: every species id in
  `Application.get_env(:mehungry, :eval_in_season)` is in season in every country
  and month. Installed by `MealPlanCatalog.seed/1` (`:seasonal_availability`
  config) so live evals exercise the seasonal-fruit snack rules without the
  separate seasonality app's data.
  """
  @behaviour Mehungry.Food.SeasonalAvailability

  @impl true
  def available_species_ids(_country, _month),
    do: Application.get_env(:mehungry, :eval_in_season, MapSet.new())

  @impl true
  def supported_countries, do: [%{code: "GR", name: "Greece"}]
end
