defmodule MehungryWeb.Api.V1.BlueprintMatch do
  @moduledoc """
  Controller-side glue for the optional `?blueprint_slug=` enrichment on recipe +
  ingredient endpoints. Resolves the referenced blueprint (public, or one the
  caller owns), batch-runs the shared `MealBlueprints` matcher over the page's
  recipes/ingredients, and serializes a per-entity `blueprint_match` block via
  `BlueprintMatchJSON`.

  Everything degrades silently: with no `blueprint_slug` (or an unknown/forbidden
  one) `blueprint/2` returns `nil`, the match maps are empty, and `block/3` yields
  `nil` — so the responses are unchanged for callers that don't ask to match.
  """

  alias Mehungry.MealBlueprints
  alias MehungryWeb.Api.V1.BlueprintMatchJSON

  @empty_report %{matches: [], violations: []}

  @doc """
  The blueprint referenced by `params["blueprint_slug"]` for the request's user,
  or `nil` when absent/unknown. Reuses `MealBlueprints.get_blueprint_by_slug/2`.
  """
  def blueprint(conn, params) do
    blueprint_for(params["blueprint_slug"], conn.assigns[:current_user])
  end

  defp blueprint_for(slug, user) when is_binary(slug) and slug != "" do
    MealBlueprints.get_blueprint_by_slug(slug, user && user.id)
  end

  defp blueprint_for(_slug, _user), do: nil

  @doc "Match map `%{recipe_id => report}` for `recipes` (`%{}` with no blueprint)."
  def recipe_reports(nil, _recipes), do: %{}
  def recipe_reports(blueprint, recipes), do: MealBlueprints.match_recipes(blueprint, recipes)

  @doc "Match map `%{ingredient_id => report}` for `ingredients` (`%{}` with no blueprint)."
  def ingredient_reports(nil, _ingredients), do: %{}

  def ingredient_reports(blueprint, ingredients),
    do: MealBlueprints.match_ingredients(blueprint, ingredients)

  @doc """
  The serialized `blueprint_match` block for entity `id` from a `reports` map, or
  `nil` when there is no blueprint context (so serializers omit the key).
  """
  def block(nil, _reports, _id), do: nil

  def block(blueprint, reports, id) do
    BlueprintMatchJSON.block(blueprint, Map.get(reports, id, @empty_report))
  end
end
