defmodule Mehungry.Food.NutrientClaims do
  @moduledoc """
  Per-serving "high in / source of" nutrient badges for a recipe.

  "High in Iron" is not a subjective call — it is a legally defined numeric
  threshold. This module applies the **EU** nutrition-claims framework
  (Reg (EC) 1924/2006 Annex, over the Reg (EU) 1169/2011 Annex XIII Part A
  Nutrient Reference Values) because the audience is ~98% Greece:

    * **"Source of" X** — the portion supplies **≥ 15%** of the nutrient's NRV.
    * **"High in" / "Rich in" X** — **≥ 30%** of the NRV (exactly double).

  The comparison basis is **per serving**, not per 100 g: per-100 g dilutes a
  watery dish (soup/stew) so everything reads "low", whereas the per-portion
  basis is both what the eater consumes and EU-legal. Per-serving is simply
  `recipe total ÷ servings`.

  This reuses the existing nutrient-tree machinery rather than re-deriving it:
  `Mehungry.NutrientUtils.find_nutrient/2` locates a nutrient anywhere in the
  stored string-keyed tree (minerals/vitamins nest under `"Minerals"`/`"Vitamins"`
  umbrella nodes), and `NutrientUtils.to_grams/2` normalizes mg/µg so the recipe
  amount and the NRV are compared on one scale. The `@nrv` labels match the
  canonical node names produced by `Food.NutrientNameNormalizer` (e.g. folate is
  stored as `"Folate (Vitamin B9)"`), so lookups resolve directly.

  NRV-backed sibling of `Mehungry.Health.NutrientTargets` (same label-driven
  shape, different purpose — public claims vs. health-recommendation resolution).

  ## Data-coverage gate

  Recipe totals silently **undercount** when some ingredients lack
  `IngredientNutrient` rows. By itself that only ever produces a false negative
  (a missed badge), but a recipe mostly built from data-less ingredients could
  still scrape past a threshold on its one data-rich ingredient and **over**-claim
  — unacceptable on a public, indexable surface. So the write path passes the
  recipe's mass-weighted coverage ratio (`NutrientCalculation.nutrient_data_coverage/1`)
  as the `:coverage` opt and `badges/3` suppresses **all** badges below
  `coverage_floor/0` (currently 0.75). Derive-on-read callers that don't pass
  `:coverage` are not gated; the gated, authoritative badges are the ones
  persisted to `recipes.badges`.

  ## Known limitations (deliberately out of scope for v1)

    * **No per-serving plausibility cap.** The coverage gate catches the common
      case (thin data), but a recipe with *present-but-wrong* nutrient data could
      still over-claim. A naive cap is risky (liver is genuinely ~1000%+ NRV
      B12), so it is a considered follow-up, not v1.
    * **Cooking losses are not modeled.** USDA values are used as-is; heat-labile
      nutrients (vitamin C, folate, thiamin) are in reality reduced by cooking, so
      badges on those are, if anything, generous. Kept conservative by relying on
      the stricter EU thresholds.
  """

  alias Mehungry.NutrientUtils

  # Canonical label => {nrv_amount, unit} — EU NRV (adult), Reg (EU) 1169/2011
  # Annex XIII Part A. Labels are the names `NutrientNameNormalizer` emits for the
  # stored tree, so `find_nutrient/2` resolves them directly.
  #
  # Chloride/Fluoride/Chromium/Molybdenum/Iodine are intentionally omitted — they
  # are rarely present in USDA ingredient data and would misfire from
  # undercounting. Sodium is omitted because it is a *reduce* nutrient, never a
  # positive "high in" badge.
  @nrv %{
    "Vitamin A" => {800, "µg"},
    "Vitamin D" => {5, "µg"},
    "Vitamin E" => {12, "mg"},
    "Vitamin K" => {75, "µg"},
    "Vitamin C" => {80, "mg"},
    "Vitamin B1 (Thiamin)" => {1.1, "mg"},
    "Vitamin B2 (Riboflavin)" => {1.4, "mg"},
    "Vitamin B3 (Niacin)" => {16, "mg"},
    "Vitamin B5 (Pantothenic Acid)" => {6, "mg"},
    "Vitamin B6" => {1.4, "mg"},
    "Vitamin B7 (Biotin)" => {50, "µg"},
    "Folate (Vitamin B9)" => {200, "µg"},
    "Vitamin B12" => {2.5, "µg"},
    "Potassium" => {2000, "mg"},
    "Calcium" => {800, "mg"},
    "Phosphorus" => {700, "mg"},
    "Magnesium" => {375, "mg"},
    "Iron" => {14, "mg"},
    "Zinc" => {10, "mg"},
    "Copper" => {1, "mg"},
    "Manganese" => {2, "mg"},
    "Selenium" => {55, "µg"}
  }

  @source_fraction 0.15
  @high_fraction 0.30

  # Nutrient-data coverage floor. Badges are suppressed entirely (not per-nutrient)
  # when the recipe's mass-weighted coverage ratio — the fraction of its grams that
  # comes from ingredients carrying IngredientNutrient data
  # (`NutrientCalculation.nutrient_data_coverage/1`) — falls below this. Below the
  # floor the recipe totals systematically undercount, so *every* claim is suspect,
  # not just one; all-or-nothing keeps the failure mode a safe false negative
  # (a missed badge) rather than a public over-claim. Callers that don't pass a
  # `:coverage` opt are not gated (e.g. derive-on-read on an already-loaded recipe,
  # which has no ingredient data to measure).
  @coverage_floor 0.75

  @doc """
  The raw NRV table: `label => {amount, unit}` (EU Annex XIII Part A).
  """
  def nrv, do: @nrv

  @doc """
  The nutrient-data coverage floor below which all badges are suppressed (see
  `@coverage_floor`).
  """
  def coverage_floor, do: @coverage_floor

  @doc """
  The URL slug for a canonical NRV `label` (e.g. `"Vitamin C"` => `"vitamin-c"`),
  used by the `/search/nutrient/:nutrient` route and the sitemap. Drops any
  parenthetical alias: `"Folate (Vitamin B9)"` => `"folate"`.
  """
  def claim_slug(label) do
    label
    |> String.replace(~r/\s*\(.*\)/, "")
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc """
  The canonical NRV label for a URL `slug`, or `nil` for an unknown slug. The
  inverse of `claim_slug/1` over the `nrv/0` set.
  """
  def label_for_slug(slug) when is_binary(slug) do
    Enum.find_value(@nrv, fn {label, _} -> if claim_slug(label) == slug, do: label end)
  end

  def label_for_slug(_), do: nil

  @doc """
  The full `%{slug => label}` map for the NRV nutrients.
  """
  def claim_slugs, do: Map.new(Map.keys(@nrv), fn label -> {claim_slug(label), label} end)

  @doc """
  The NRV for `label` expressed in grams, or `nil` for an unknown label.
  """
  def nrv_grams(label) do
    case Map.get(@nrv, label) do
      {amount, unit} ->
        case NutrientUtils.to_grams(amount, unit) do
          {:ok, grams} -> grams
          :error -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Convenience over `badges/3` for a recipe struct/map: reads its stored
  `:nutrients` tree and `:servings`.
  """
  def badges_for_recipe(recipe, opts \\ []) do
    badges(Map.get(recipe, :nutrients) || %{}, Map.get(recipe, :servings), opts)
  end

  @doc """
  Nutrient badges earned by one serving of a recipe.

  Given the whole-recipe `nutrients` tree (the string-keyed shape stored in
  `recipe.nutrients`) and the recipe `servings`, returns a list of

      %{nutrient: label, level: :high | :source, percent_nrv: integer}

  sorted by `percent_nrv` descending. `percent_nrv` is the share of the EU NRV
  one serving supplies (so a `:high` badge is ≥ 30, a `:source` badge 15–29).

  By default both tiers are returned so the caller/UI can decide which to render;
  pass `level: :high` to keep only the strong "high in" claims.

  ## Options

    * `:level` — `:high` to keep only the strong "high in" claims; omitted/any
      other value returns both tiers.
    * `:coverage` — the recipe's mass-weighted nutrient-data coverage ratio
      (`NutrientCalculation.nutrient_data_coverage/1`). When supplied and below
      `coverage_floor/0`, **all** badges are suppressed (returns `[]`) because the
      totals undercount and no claim can be trusted. When omitted the result is
      not coverage-gated — so derive-on-read callers (which have no ingredient
      data to measure) behave exactly as before; the authoritative, gated badges
      are the ones the write path persists to `recipes.badges`.

  Robustness:

    * `servings` that is nil / non-numeric / `<= 0` falls back to `1` (the raw
      total), mirroring `NutrientUtils.consumed_fraction/1`.
    * A nutrient missing from the tree, carrying a non-numeric amount, or stored
      in a non-mass unit (e.g. vitamin A/D in IU, where `to_grams/2` returns
      `:error`) is **skipped** — no badge rather than a wrong one.
  """
  def badges(nutrients, servings, opts \\ []) do
    coverage = Keyword.get(opts, :coverage)

    if is_number(coverage) and coverage < @coverage_floor do
      []
    else
      divisor = servings_divisor(servings)
      level_filter = Keyword.get(opts, :level)

      @nrv
      |> Enum.flat_map(fn {label, nrv} -> badge(nutrients, label, nrv, divisor, level_filter) end)
      |> Enum.sort_by(& &1.percent_nrv, :desc)
    end
  end

  # The badge (as a 0/1-element list, for `flat_map`) for one nutrient, or `[]`
  # when it isn't present, isn't mass-convertible, or doesn't clear the threshold.
  defp badge(nutrients, label, {nrv_amount, nrv_unit}, divisor, level_filter) do
    with node when is_map(node) <- NutrientUtils.find_nutrient(nutrients, label),
         amount when is_number(amount) <- node["amount"],
         {:ok, grams} <- NutrientUtils.to_grams(amount, node["measurement_unit"] || ""),
         {:ok, nrv_g} when nrv_g > 0 <- NutrientUtils.to_grams(nrv_amount, nrv_unit),
         fraction = grams / divisor / nrv_g,
         level when not is_nil(level) <- classify(fraction, level_filter) do
      [%{nutrient: label, level: level, percent_nrv: round(fraction * 100)}]
    else
      _ -> []
    end
  end

  @doc """
  Like `badges/3` but shaped for persistence in the `recipes.badges` jsonb
  column: string keys and a string `level`, e.g.

      %{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}

  This is what `Recipes.put_nutrient_info/2` stores. Reads of the column come
  back in this exact shape (jsonb has no atoms), mirroring how `recipe.nutrients`
  is atom-keyed in memory but string-keyed once reloaded.
  """
  def badges_for_storage(nutrients, servings, opts \\ []) do
    nutrients
    |> badges(servings, opts)
    |> Enum.map(fn %{nutrient: nutrient, level: level, percent_nrv: percent_nrv} ->
      %{"nutrient" => nutrient, "level" => Atom.to_string(level), "percent_nrv" => percent_nrv}
    end)
  end

  defp classify(fraction, :high) do
    if fraction >= @high_fraction, do: :high, else: nil
  end

  defp classify(fraction, _any) do
    cond do
      fraction >= @high_fraction -> :high
      fraction >= @source_fraction -> :source
      true -> nil
    end
  end

  defp servings_divisor(servings) when is_number(servings) and servings > 0, do: servings * 1.0
  defp servings_divisor(_servings), do: 1.0
end
