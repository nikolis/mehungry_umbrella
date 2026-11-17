defmodule MehungryWeb.Api.V1.FoodJSON do
  @moduledoc "Serializers for food species (spec §8)."

  @doc "A species list row."
  def species_summary(species) do
    %{
      id: species.id,
      name: species.name,
      slug: slug(species.name),
      icon: Mehungry.Food.species_icon(species),
      image: species_image(species),
      variety: species.variety,
      family: species.family,
      scientific_name: species.scientific_name,
      alternative_name: species.alternative_name
    }
  end

  # A licence-gated Wikimedia Commons photo + its attribution, or nil (client falls
  # back to `icon`). The attribution fields are always present so the client can
  # render the credit, which we show even where the licence doesn't demand it.
  defp species_image(%{image_url: url} = species) when is_binary(url) and url != "" do
    %{
      url: url,
      license: species.image_license,
      license_url: species.image_license_url,
      attribution: species.image_attribution,
      source_url: species.image_source_url
    }
  end

  defp species_image(_), do: nil

  @doc """
  Full species detail. `research` is a list of `SpeciesMinedFact` structs (mined
  biomedical facts from `Mehungry.FactMining`); `ingredients` is the resolved
  list; `facts` is the `fact_key => SpeciesFact` map from
  `Food.promoted_species_facts_for_species/2` (promoted enrichment facts).
  """
  def species_detail(species, research, ingredients, facts \\ %{}) do
    %{
      data:
        species_summary(species)
        |> Map.merge(%{
          research: Enum.map(research, &research_fact/1),
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

  # A mined biomedical fact. Only commercial_ok quotes are populated (non-commercial
  # quotes are withheld upstream); render from `text` + `pmid` + `label`. `lay` is the
  # miner's presentation hint (tier lead/show/hide, clarity, flags) — orthogonal to
  # `label` — so the client can apply the same lead/show/hide policy as the web page.
  defp research_fact(fact) do
    %{
      text: fact.text,
      label: fact.label,
      certainty: fact.certainty,
      claim_type: fact.claim_type,
      study_design: fact.study_design,
      source: fact.source,
      pmid: fact.pmid,
      license: fact.license,
      quote: fact.quote,
      lay: %{
        tier: fact.lay_tier,
        clarity: fact.lay_clarity,
        flags: fact.lay_flags || []
      }
    }
  end

  @doc "Derive the URL slug from a name (inverse of get_species_by_slug/1)."
  def slug(nil), do: nil

  def slug(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
