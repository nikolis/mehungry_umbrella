defmodule MehungryWeb.Api.V1.FoodJSON do
  @moduledoc "Serializers for food species (spec §8)."

  alias Mehungry.Food.SpeciesNutritionSummary
  alias MehungryWeb.NutrientLabels

  @doc """
  A species list row. `name` is localized to `locale` when the species has a
  translation for it (needs `:translations` preloaded; falls back to the English
  name otherwise). `canonical_name` is always the English name and `slug` is always
  derived from it, so both are stable across locales.
  """
  def species_summary(species, locale \\ "en") do
    %{
      id: species.id,
      name: localized_name(species, locale),
      canonical_name: species.name,
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

  # The species' translated name for `locale` (first translation, as the web page
  # picks), else its English name.
  defp localized_name(%{translations: translations} = species, locale)
       when is_list(translations) and locale not in [nil, "en"] do
    case Enum.find(translations, &(&1.language_name == locale)) do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> species.name
    end
  end

  defp localized_name(species, _locale), do: species.name

  @doc """
  Full species detail. `research` is the curated research block —
  `%{counts:, relevant:, mechanistic:, mechanistic_count:}` (the map from
  `FactMining.curated_facts_for_species/2` plus the tally from
  `FactMining.research_counts_for_species/1`); `ingredients` is the resolved,
  name-sorted list; `facts` is the `fact_key => SpeciesFact` map from
  `Food.promoted_species_facts_for_species/2` (promoted enrichment facts).

  `opts`: `:locale` (localizes `name`), `:default_ingredient` (the ingredient flagged `default: true`),
  `:recipes` (sample recipes using the species' ingredients) and `:recipes_count`
  (the true distinct count).
  """
  def species_detail(species, research, ingredients, facts \\ %{}, opts \\ []) do
    default_id =
      case opts[:default_ingredient] do
        %{id: id} -> id
        _ -> nil
      end

    %{
      data:
        species_summary(species, opts[:locale] || "en")
        |> Map.merge(%{
          research: research_block(research),
          ingredients:
            Enum.map(ingredients, &%{id: &1.id, name: &1.name, default: &1.id == default_id}),
          facts: facts_block(facts),
          recipes: Enum.map(opts[:recipes] || [], &species_recipe/1),
          recipes_count: opts[:recipes_count] || 0
        })
    }
  end

  @doc """
  Per-100g nutrition of one of a species' ingredients: the headline macro cards,
  the localized hierarchical nutrient `tree` (same shape as recipe `nutrients`) and
  the deterministic summary sentences the web page shows above its breakdown.
  `ingredient` needs `ingredient_nutrients: [nutrient: :measurement_unit]` preloaded.
  """
  def species_nutrition(species, ingredient, tree, locale) do
    summary =
      [
        SpeciesNutritionSummary.composition_summary(ingredient.name, tree),
        SpeciesNutritionSummary.micronutrient_summary(species.name, tree)
      ]
      |> Enum.reject(&is_nil/1)

    %{
      data: %{
        ingredient: %{id: ingredient.id, name: ingredient.name},
        top:
          ingredient.ingredient_nutrients
          |> SpeciesNutritionSummary.top_nutrients()
          |> Enum.map(&top_nutrient(&1, locale)),
        nutrients: MehungryWeb.Api.V1.JSON.Helpers.localize_nutrients(tree, locale),
        summary: summary
      }
    }
  end

  # ── parts ────────────────────────────────────────────────────────────────

  # A headline macro card. `key` is the stable identifier ("calories", "protein",
  # "fat", "carbs", "fiber"); `label` is its localized display name.
  defp top_nutrient(%{label: label, amount: amount, unit: unit}, locale) do
    %{
      key: String.downcase(label),
      label: Gettext.with_locale(locale || "en", fn -> NutrientLabels.translate_name(label) end),
      amount: amount,
      unit: SpeciesNutritionSummary.macro_unit(unit)
    }
  end

  defp research_block(research) do
    counts = research[:counts] || %{}

    %{
      counts: %{
        total: counts[:total] || 0,
        verified: counts[:verified] || 0,
        contradicted: counts[:contradicted] || 0,
        unverified: counts[:unverified] || 0
      },
      relevant: Enum.map(research[:relevant] || [], &research_fact/1),
      mechanistic: Enum.map(research[:mechanistic] || [], &research_fact/1),
      mechanistic_count: research[:mechanistic_count] || 0
    }
  end

  # A recipe using one of the species' ingredients (the "Recipes with <food>" row).
  defp species_recipe(recipe) do
    %{
      id: recipe.id,
      title: recipe.title,
      image_url: recipe.image_url,
      list_image_url: recipe.list_image_url || recipe.image_url,
      cook_time_min: recipe.cooking_time_lower_limit
    }
  end

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
  # `label`. `reason` is the verifier's explanation of the verdict (the web page's
  # "Why?" disclosure), nil when absent.
  @doc "A mined biomedical fact (see `species_detail/5` and the research search)."
  def research_fact(fact) do
    %{
      text: fact.text,
      label: fact.label,
      reason: presence(fact.reason),
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

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_), do: nil

  @doc "Derive the URL slug from a name (inverse of get_species_by_slug/1)."
  def slug(nil), do: nil

  def slug(name) do
    name |> String.downcase() |> String.replace(" ", "-")
  end
end
