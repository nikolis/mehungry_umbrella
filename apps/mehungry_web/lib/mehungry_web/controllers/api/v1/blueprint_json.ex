defmodule MehungryWeb.Api.V1.BlueprintJSON do
  @moduledoc """
  Serializers for public meal blueprints (the mobile "Meal Blueprints" browse +
  detail surface). A blueprint is a reusable 7-day targets document; the summary
  powers the browse list, the detail carries the full day/meal tree.
  """

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.MealBlueprints

  @doc """
  A blueprint list row. `saved_ids` is the set of blueprint ids the viewer has
  saved (empty for an anonymous caller), so each row carries a `saved` flag.
  """
  def summary(blueprint, saved_ids \\ []) do
    %{
      id: blueprint.id,
      name: blueprint.name,
      slug: blueprint.slug,
      description: blueprint.description,
      visibility: blueprint.visibility,
      condition: condition_name(blueprint),
      plans_count: blueprint.plans_count || 0,
      owner: owner(blueprint),
      saved: blueprint.id in saved_ids,
      inserted_at: utc(blueprint.inserted_at)
    }
  end

  @doc "Full blueprint detail: the summary merged with the structured targets tree."
  def detail(blueprint, saved_ids \\ []) do
    targets = MealBlueprints.to_targets_map(blueprint)

    data =
      summary(blueprint, saved_ids)
      |> Map.merge(%{
        required_nutrients: targets.required_nutrients,
        avoid_nutrients: targets.avoid_nutrients,
        required_nutrient_pcts: targets.required_nutrient_pcts,
        avoid_nutrient_pcts: targets.avoid_nutrient_pcts,
        required_nutrient_modes: targets.required_nutrient_modes,
        avoid_nutrient_modes: targets.avoid_nutrient_modes,
        required_compounds: targets.required_compounds,
        avoid_compounds: targets.avoid_compounds,
        preferred_foods: targets.preferred_foods,
        avoid_foods: targets.avoid_foods,
        days: targets.days
      })

    data(data)
  end

  # ── parts ──────────────────────────────────────────────────────────────────

  defp condition_name(%{condition: %{name: name}}), do: name
  defp condition_name(_), do: nil

  # The owning (nutritionist) user; `profile_slug` is their public profile slug
  # when they have a professional profile, so the client can deep-link to it.
  defp owner(%{user: %Ecto.Association.NotLoaded{}}), do: nil
  defp owner(%{user: nil}), do: nil

  defp owner(%{user: user}) do
    %{
      id: user.id,
      name: user.name,
      profile_slug: profile_slug(user)
    }
  end

  defp owner(_), do: nil

  defp profile_slug(%{professional_profile: %{slug: slug}}), do: slug
  defp profile_slug(_), do: nil
end
