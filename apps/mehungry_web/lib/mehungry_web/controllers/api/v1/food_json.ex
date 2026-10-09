defmodule MehungryWeb.Api.V1.FoodJSON do
  @moduledoc "Serializers for food species and health conditions (spec §8)."

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
  `summary` is `{:ok, IngredientCompoundSummary} | {:error, _}`; `conditions` and
  `ingredients` are the resolved lists.
  """
  def species_detail(species, compounds, conditions, ingredients) do
    %{
      data:
        species_summary(species)
        |> Map.merge(%{
          compounds: Enum.map(compounds, &compound/1),
          related_conditions: Enum.map(conditions, &related_condition/1),
          ingredients: Enum.map(ingredients, &%{id: &1.id, name: &1.name})
        })
    }
  end

  def condition_summary(condition) do
    %{
      id: condition.id,
      name: condition.name,
      category: condition.category,
      slug: slug(condition.name)
    }
  end

  @doc "Condition detail with compound recommendations + implicated species."
  def condition_detail(condition, recommendations, species_rows) do
    %{
      data:
        condition_summary(condition)
        |> Map.merge(%{
          description: condition.description,
          compound_recommendations: Enum.map(recommendations, &compound_recommendation/1),
          species: Enum.map(species_rows, &condition_species/1)
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

  defp related_condition(%{condition: condition} = row) do
    %{
      id: condition.id,
      name: condition.name,
      recommendation: row[:recommendation],
      severity: row[:severity]
    }
  end

  defp compound_recommendation(rec) do
    %{
      compound: rec.compound && rec.compound.name,
      recommendation: rec.recommendation,
      severity: rec.severity,
      evidence_level: rec.evidence_level,
      source: rec.source
    }
  end

  defp condition_species(%{species: species} = row) do
    %{
      id: species.id,
      name: species.name,
      slug: slug(species.name),
      reason_compound: row[:compound] && row.compound.name
    }
  end

  @doc "Derive the URL slug from a name (inverse of get_species_by_slug/1)."
  def slug(nil), do: nil

  def slug(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
