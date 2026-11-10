defmodule MehungryWeb.Api.V1.FoodJSON do
  @moduledoc "Serializers for food species (spec §8)."

  @doc "A species list row."
  def species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      slug: slug(species.name),
      icon: Mehungry.Food.species_icon(species),
      variety: species.variety,
      family: species.family,
      scientific_name: species.scientific_name,
      alternative_name: species.alternative_name
    }
  end

  @doc """
  Full species detail. `compounds` is a list of `%{compound, summary}` where
  `summary` is `{:ok, IngredientCompoundSummary} | {:error, _}`; `ingredients`
  is the resolved list; `facts` is the `fact_key => SpeciesFact` map from
  `Food.promoted_species_facts_for_species/2` (promoted enrichment facts).
  """
  def species_detail(species, compounds, ingredients, facts \\ %{}) do
    %{
      data:
        species_summary(species)
        |> Map.merge(%{
          compounds: Enum.map(compounds, &compound/1),
          ingredients: Enum.map(ingredients, &%{id: &1.id, name: &1.name}),
          facts: facts_block(facts)
        })
    }
  end

  # ── parts ────────────────────────────────────────────────────────────────

  # Promoted enrichment facts (Wikidata CC0 + FAOSTAT CC BY). Producers carry the
  # required FAOSTAT attribution; only ranked country names + year are exposed (no tonnage).
  defp facts_block(facts) do
    %{
      origin_region: fact_text(facts, "origin_region"),
      description: fact_text(facts, "description"),
      wikipedia_url: fact_text(facts, "wikipedia_url"),
      top_producers: producers_block(facts["top_producers"])
    }
  end

  defp fact_text(facts, key) do
    case facts[key] do
      %{value_text: text} when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  defp producers_block(%{value_json: %{"producers" => producers}}) when is_list(producers) do
    year =
      case producers do
        [%{"year" => year} | _] -> year
        _ -> nil
      end

    %{
      countries: producers |> Enum.map(& &1["country"]) |> Enum.reject(&is_nil/1),
      year: year,
      source: "FAO FAOSTAT (CC BY 4.0)"
    }
  end

  defp producers_block(_), do: nil

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
