defmodule MehungryWeb.Api.V1.FoodJSON do
  @moduledoc "Serializers for food species (spec §8)."

  @doc "A species list row."
  def species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      slug: slug(species.name),
      variety: species.variety,
      family: species.family,
      scientific_name: species.scientific_name,
      alternative_name: species.alternative_name
    }
  end

  @doc """
  Full species detail. `compounds` is a list of `%{compound, summary}` where
  `summary` is `{:ok, IngredientCompoundSummary} | {:error, _}`; `ingredients`
  is the resolved list.
  """
  def species_detail(species, compounds, ingredients) do
    %{
      data:
        species_summary(species)
        |> Map.merge(%{
          compounds: Enum.map(compounds, &compound/1),
          ingredients: Enum.map(ingredients, &%{id: &1.id, name: &1.name})
        })
    }
  end

  # ── parts ────────────────────────────────────────────────────────────────

  defp compound(%{compound: compound, summary: {:ok, s}}) do
    %{
      name: compound.name,
      mean: s.mean,
      unit: s.unit,
      range: [s.min, s.max],
      variance: s.variance,
      evidence_score: s.evidence_score,
      study_count: s.study_count
    }
  end

  defp compound(%{compound: compound, summary: _}) do
    %{name: compound.name, mean: nil, unit: nil, range: nil, study_count: 0}
  end

  @doc "Derive the URL slug from a name (inverse of get_species_by_slug/1)."
  def slug(nil), do: nil

  def slug(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
