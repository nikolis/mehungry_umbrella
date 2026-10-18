defmodule MehungryWeb.NutrientLabels do
  @moduledoc """
  Single source of truth for localized nutrient **display** labels.

  The nutrition breakdown renders a normalized, code-defined vocabulary — the
  canonical names emitted by `Mehungry.Food.NutrientNameNormalizer.normalize/1`
  (every distinct `Nutrient.name` passes through it), plus the synthetic grouping
  nodes synthesized by `NutrientHierarchyBuilder` ("Vitamins", "Minerals",
  "Dietary Fiber", …) which have **no backing `Nutrient` row** — NOT raw
  `Nutrient.name` values. These strings are therefore UI text and are translated
  via Gettext here, not through the DB `nutrient_translations` table (keyed on raw
  `Nutrient.name`, which would miss the grouping nodes and the normalized names).

  `@vocabulary` is the full set of non-fatty-acid display names that can appear
  (derived from every `Nutrient.name` in the DB + the synthetic group nodes + the
  short macro-card labels). One `gettext/1` clause is generated per entry so
  `mix gettext.extract` discovers them. Unknown names — including the individual
  fatty-acid common names, which we intentionally leave in English — fall through
  unchanged, so the gate is always safe to call on any nutrient name.

  This is the one place the vocabulary lives; the nutrition accordion, the species
  "Nutritional Highlights" cards, and the calendar macro pie all route labels here.
  """
  use Gettext, backend: MehungryWeb.Gettext

  @vocabulary [
    "10-formyl Folic Acid (10hcofa)",
    "25-hydroxycholecalciferol",
    "5-formyltetrahydrofolic Acid (5-hcoh4",
    "Added Sugars",
    "Alcohol, Ethyl",
    "Amino Acids",
    "Arginine",
    "Ash",
    "Aspartic Acid",
    "Beta-glucan",
    "Beta-sitostanol",
    "Beta-sitosterol",
    "Betaine",
    "Boron, B",
    "Brassicasterol",
    "Caffeine",
    "Calcium",
    "Calories",
    "Campestanol",
    "Campesterol",
    "Carbohydrates",
    "Carbs",
    "Carotene, Alpha",
    "Carotene, Beta",
    "Carotene, Gamma",
    "Cholesterol",
    "Choline",
    "Cis-beta-carotene",
    "Cis-lutein/zeaxanthin",
    "Cis-lycopene",
    "Citric Acid",
    "Cobalt, Co",
    "Complex Carbohydrates",
    "Copper",
    "Cryptoxanthin, Alpha",
    "Cryptoxanthin, Beta",
    "Cysteine",
    "Cystine",
    "Daidzein",
    "Daidzin",
    "Delta-5-avenasterol",
    "Delta-7-stigmastenol",
    "Dietary Fiber",
    "Disaccharides",
    "Energy",
    "Ergosta-5,7-dienol",
    "Ergosta-7,22-dienol",
    "Ergosta-7-enol",
    "Ergosterol",
    "Ergothioneine",
    "Fat",
    "Fiber",
    "Fluoride, F",
    "Folate (Vitamin B9)",
    "Folic Acid",
    "Fructose",
    "Galactose",
    "Genistein",
    "Genistin",
    "Glucose",
    "Glutamic Acid",
    "Glutathione",
    "Glycine",
    "Glycitin",
    "High Molecular Weight Dietary Fiber (HMWDF)",
    "Histidine",
    "Hydroxyproline",
    "Iodine, I",
    "Iron",
    "Isoflavones",
    "Isoleucine",
    "Lactose",
    "Leucine",
    "Lipids",
    "Low Molecular Weight Dietary Fiber (LMWDF)",
    "Lutein",
    "Lutein + Zeaxanthin",
    "Lycopene",
    "Lysine",
    "Magnesium",
    "Malic Acid",
    "Maltose",
    "Manganese",
    "Methionine",
    "Minerals",
    "Molybdenum, Mo",
    "Monosaccharides",
    "Monounsaturated Fat",
    "Net Carbs",
    "Nickel, Ni",
    "Nitrogen",
    "Oligosaccharides",
    "Organic Acids",
    "Oxalic Acid",
    "Phosphorus",
    "Phytoene",
    "Phytofluene",
    "Phytosterols",
    "Phytosterols, Other",
    "Polyunsaturated Fat",
    "Potassium",
    "Proline",
    "Protein",
    "Proximates",
    "Pyruvic Acid",
    "Quinic Acid",
    "Raffinose",
    "Resistant Starch",
    "Retinol",
    "Saturated Fat",
    "Selenium",
    "Serine",
    "Sodium",
    "Specific Gravity",
    "Stachyose",
    "Starch",
    "Stigmastadiene",
    "Stigmasterol",
    "Sucrose",
    "Sugar Alcohols",
    "Sulfur, S",
    "Theobromine",
    "Threonine",
    "Tocopherol, Beta",
    "Tocopherol, Delta",
    "Tocopherol, Gamma",
    "Tocotrienol, Alpha",
    "Tocotrienol, Beta",
    "Tocotrienol, Delta",
    "Tocotrienol, Gamma",
    "Total Fat",
    "Total Sugars",
    "Trans Fat",
    "Trans-beta-carotene",
    "Trans-lycopene",
    "Tryptophan",
    "Tyrosine",
    "Valine",
    "Verbascose",
    "Vitamin A",
    "Vitamin B1 (Thiamin)",
    "Vitamin B12",
    "Vitamin B2 (Riboflavin)",
    "Vitamin B3 (Niacin)",
    "Vitamin B5 (Pantothenic Acid)",
    "Vitamin B6",
    "Vitamin B7 (Biotin)",
    "Vitamin C",
    "Vitamin D",
    "Vitamin E",
    "Vitamin K",
    "Vitamins",
    "Vitamins And Other Components",
    "Water",
    "Zeaxanthin",
    "Zinc"
  ]

  @doc "The English display vocabulary this module can translate."
  def vocabulary, do: @vocabulary

  @doc """
  Translates every `name` in a nutrient node / list of nodes / `name => node`
  map for `locale`, recursing through `children` (mirrors
  `Mehungry.Food.Nutrition.FattyAcidMatcher.resolve_names/1`). Must run **after**
  `resolve_names/1` so fatty-acid nodes are keyed on their final English display
  string. No-op for the source locale.

  Translates by walking the tree under `Gettext.with_locale/2` and calling
  `translate_name/1` per node — the same live-Gettext path the highlight cards and
  calendar pie use. (It deliberately does **not** memoize: a cached map would go
  stale when the `.po` changes under a long-running node, since the cache key
  can't see translation edits.)
  """
  def translate_names(nodes, locale) when locale in [nil, "en", "En"], do: nodes

  def translate_names(nodes, locale) do
    Gettext.with_locale(locale, fn -> remap(nodes) end)
  end

  defp remap(nodes) when is_list(nodes), do: Enum.map(nodes, &remap/1)

  defp remap(node) when is_map(node) and not is_struct(node) do
    node =
      case node_get(node, "name") do
        name when is_binary(name) -> node_put(node, "name", translate_name(name))
        _ -> node
      end

    case node_get(node, "children") do
      children when is_list(children) and children != [] ->
        node_put(node, "children", Enum.map(children, &remap/1))

      _ ->
        node
    end
  end

  defp remap(other), do: other

  @doc """
  Translates a stored `name => node` nutrient map (the shape persisted in
  `recipe.nutrients` and returned by `NutrientUtils.summarize_meals_nutrients/1`)
  — both the top-level **keys** and every node `name`, recursing into `children`.
  No-op for the source locale. Expects fatty-acid leaves already resolved to their
  English display names (run `FattyAcidMatcher.resolve_names/1` first); the REST
  serializers compose both. Used by the `/api/v1` nutrient surfaces so the mobile
  client gets the same localized labels as the web accordion.
  """
  def translate_tree(map, locale) when is_map(map) and locale not in [nil, "en", "En"] do
    Gettext.with_locale(locale, fn ->
      Map.new(map, fn {name, node} -> {translate_name(name), remap(node)} end)
    end)
  end

  def translate_tree(map, _locale), do: map

  # Read/write a node key tolerant of string- or atom-keyed maps.
  defp node_get(node, key), do: Map.get(node, key) || Map.get(node, String.to_atom(key))

  defp node_put(node, key, value) do
    if Map.has_key?(node, key),
      do: Map.put(node, key, value),
      else: Map.put(node, String.to_atom(key), value)
  end

  @doc """
  Localized label for a single nutrient display name, using the Gettext locale in
  effect (the current process locale, set by `SetLocale`/`RestoreLocale`, or
  whatever `display_names_map/1` forces via `Gettext.with_locale/2`). Unknown names
  — including the individual fatty-acid common names we leave in English — pass
  through unchanged.
  """
  for name <- @vocabulary do
    def translate_name(unquote(name)), do: gettext(unquote(name))
  end

  def translate_name(other), do: other
end
