defmodule Mehungry.FoodData.MyPlate.IngredientParser do
  @moduledoc """
  Parses a MyPlate free-text ingredient line into the normalized shape that
  `Mehungry.FoodData.RecipeIngredientResolver` consumes.

  MyPlate serves each ingredient as `%{"text" => "1 1/2 cups whole wheat flour",
  "note" => "all-purpose"}` — a human string plus an optional qualifier — rather
  than structured quantity/unit/name fields (unlike Spoonacular). This module
  splits the `text` into `%{name, quantity, unit, original}`:

    * **quantity** — leading integer, decimal, simple fraction (`1/2`), mixed
      fraction (`1 1/2`), or unicode fraction (`½`); a numeric range (`2-3`,
      `2 to 3`) takes the lower bound. No leading number → `1.0`.
    * **unit** — the next token if it's a recognized cooking unit (`cups`,
      `teaspoon`, `oz`, `clove`…), canonicalized to a form the resolver knows.
      A non-unit next token (e.g. `eggs`) means a count item → unit `"piece"`.
    * **name** — the remainder (a leading `"of "` stripped), used for the
      ingredient relevance search.
    * **original** — the verbatim display text with the `note` appended in
      parens, preserved for `ingredient_allias` but kept out of the search name.

  Pure and DB-free.
  """

  # Recognized cooking units. Membership decides whether the token after the
  # quantity is a unit (consumed) or the start of the ingredient name (count item).
  @units ~w(
    cup cups
    tablespoon tablespoons tbsp tbsps tbs
    teaspoon teaspoons tsp tsps
    ounce ounces oz
    pound pounds lb lbs
    gram grams g gr
    kilogram kilograms kg
    milligram milligrams mg
    milliliter milliliters ml
    liter liters litre litres l
    pint pints pt
    quart quarts qt
    gallon gallons gal
    pinch pinches
    dash dashes
    can cans
    package packages pkg pkgs
    clove cloves
    slice slices
    stick sticks
    piece pieces
    bunch bunches
    stalk stalks
    head heads
    container containers
    box boxes
    bag bags
    jar jars
    bottle bottles
    packet packets
    sprig sprigs
    fillet fillets
    wedge wedges
  )

  @unit_set MapSet.new(@units)

  # Abbreviations / variants → the form the resolver resolves best. Units the
  # resolver can't convert anyway (pint, quart…) are left as-is; they simply land
  # in the importer's `unmatched` list, which is fine.
  @unit_canon %{
    "tbsp" => "tablespoon",
    "tbsps" => "tablespoon",
    "tbs" => "tablespoon",
    "tsp" => "teaspoon",
    "tsps" => "teaspoon",
    "oz" => "ounce",
    "lb" => "pound",
    "lbs" => "pound",
    "pkg" => "package",
    "pkgs" => "package",
    "gr" => "g"
  }

  # Unicode vulgar fractions → an ascii " n/d" (leading space handles "1½").
  @unicode_fractions %{
    "½" => " 1/2",
    "⅓" => " 1/3",
    "⅔" => " 2/3",
    "¼" => " 1/4",
    "¾" => " 3/4",
    "⅕" => " 1/5",
    "⅖" => " 2/5",
    "⅗" => " 3/5",
    "⅘" => " 4/5",
    "⅙" => " 1/6",
    "⅚" => " 5/6",
    "⅐" => " 1/7",
    "⅛" => " 1/8",
    "⅜" => " 3/8",
    "⅝" => " 5/8",
    "⅞" => " 7/8",
    "⅑" => " 1/9",
    "⅒" => " 1/10"
  }

  @doc """
  Parses one ingredient line. Returns `%{name, quantity, unit, original}`.
  `note` (the MyPlate qualifier, may be `nil`) is folded into `original` only.
  """
  def parse(text, note \\ nil) do
    original = build_original(text, note)

    normalized = normalize_fractions(text || "")
    {quantity, rest} = parse_quantity(normalized)
    {unit, name} = parse_unit_and_name(rest)

    %{
      name: String.trim(name),
      quantity: quantity || 1.0,
      unit: unit,
      original: original
    }
  end

  # ── quantity ──────────────────────────────────────────────────────────────

  defp normalize_fractions(text) do
    @unicode_fractions
    |> Enum.reduce(text, fn {uni, ascii}, acc -> String.replace(acc, uni, ascii) end)
    |> String.replace(~r/\s+/, " ")
  end

  # Leading mixed/simple fraction ("1 1/2", "1/2"), else decimal/integer, else none.
  defp parse_quantity(str) do
    cond do
      m = Regex.run(~r{^\s*(?:(\d+)\s+)?(\d+)/(\d+)(.*)$}s, str) ->
        [_, whole, num, den, rest] = m
        w = if whole in [nil, ""], do: 0, else: String.to_integer(whole)
        q = w + String.to_integer(num) / String.to_integer(den)
        {q, strip_range(rest)}

      m = Regex.run(~r/^\s*(\d+(?:\.\d+)?)(.*)$/s, str) ->
        [_, num, rest] = m
        {parse_num(num), strip_range(rest)}

      true ->
        {nil, str}
    end
  end

  # After a leading number, drop a "-3" / "– 3" / "to 3" range tail so the upper
  # bound doesn't leak into the ingredient name (we keep the lower bound as the
  # quantity). A dash separator may abut the next number ("2-3"); "to" needs a
  # space ("2 to 3") so it isn't confused with a word.
  defp strip_range(rest) do
    case Regex.run(~r{^\s*(?:[-–—]\s*|to\s+)\d+(?:\.\d+)?(?:\s+\d+/\d+)?\b(.*)$}s, rest) do
      [_, tail] -> tail
      nil -> rest
    end
  end

  defp parse_num(num) do
    if String.contains?(num, "."), do: String.to_float(num), else: String.to_integer(num) * 1.0
  end

  # ── unit + name ─────────────────────────────────────────────────────────────

  defp parse_unit_and_name(rest) do
    rest = String.trim(rest)

    case String.split(rest, ~r/\s+/, parts: 2) do
      [""] ->
        {"piece", ""}

      [word] ->
        maybe_unit(word, "", rest)

      [word, tail] ->
        maybe_unit(word, tail, rest)
    end
  end

  # If `word` is a recognized unit, consume it and the name is `tail` (minus a
  # leading "of "). Otherwise it's a count item: unit "piece", name the whole rest.
  defp maybe_unit(word, tail, full_rest) do
    token = word |> String.downcase() |> String.trim_trailing(".")

    if MapSet.member?(@unit_set, token) do
      {Map.get(@unit_canon, token, token), strip_leading_of(tail)}
    else
      {"piece", full_rest}
    end
  end

  defp strip_leading_of(name) do
    String.replace(name, ~r/^\s*of\s+/i, "")
  end

  # ── original (display) ────────────────────────────────────────────────────

  defp build_original(text, note) do
    text = String.trim(text || "")

    case note && String.trim(note) do
      nil -> text
      "" -> text
      note -> "#{text} (#{note})"
    end
  end
end
