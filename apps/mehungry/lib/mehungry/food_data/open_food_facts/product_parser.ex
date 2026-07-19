defmodule Mehungry.FoodData.OpenFoodFacts.ProductParser do
  @moduledoc """
  Pure parsing of Open Food Facts product JSON (one JSONL dump line or a
  v2 API `product` map) into `food_products` attrs plus translation rows.

  No IO happens here — the bulk importer, delta worker, and API fallback all
  flow through these functions so filtering/normalization is defined once.
  """

  # OFF country tags for the markets we import: EU-27 plus UK, Switzerland,
  # Norway, Iceland and Liechtenstein.
  @european_tags MapSet.new(~w(
    en:austria en:belgium en:bulgaria en:croatia en:cyprus en:czech-republic
    en:denmark en:estonia en:finland en:france en:germany en:greece en:hungary
    en:ireland en:italy en:latvia en:lithuania en:luxembourg en:malta
    en:netherlands en:poland en:portugal en:romania en:slovakia en:slovenia
    en:spain en:sweden
    en:united-kingdom en:switzerland en:norway en:iceland en:liechtenstein
  ))

  @barcode_format ~r/^\d{8,14}$/

  # Postgres :string columns are varchar(255); OFF free-text fields can be longer.
  @string_limit 255

  @doc """
  Parses one line of the OFF JSONL dump.

  Returns `{:ok, attrs, translations}`, `:skip` (invalid barcode, no name, or
  not sold in a European country), or `{:error, reason}` for undecodable JSON.

  `known_languages` is a `MapSet` of language codes present in the `languages`
  table — translations for other languages are dropped.
  """
  def parse_line(json_line, %MapSet{} = known_languages) do
    case Jason.decode(json_line) do
      {:ok, product} when is_map(product) ->
        parse_product(product, known_languages, require_european: true)

      {:ok, _other} ->
        :skip

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a product map from the v2 read API (barcode-scan fallback path).
  Does not require a European country tag — a user scanned it, so we keep it.
  """
  def parse_api_product(product, %MapSet{} = known_languages) when is_map(product) do
    parse_product(product, known_languages, require_european: false)
  end

  @doc """
  Shared core: OFF product map → `{:ok, attrs, translations} | :skip`.
  """
  def parse_product(product, %MapSet{} = known_languages, opts) when is_map(product) do
    countries = countries_tags(product)

    with {:ok, barcode} <- normalize_barcode(product["code"] || product["_id"]),
         :ok <- check_european(countries, Keyword.get(opts, :require_european, true)),
         translations = extract_translations(product, known_languages),
         {:ok, name} <- pick_name(product, translations) do
      attrs = %{
        barcode: barcode,
        name: truncate(name),
        brands: truncate(product["brands"]),
        quantity: truncate(product["quantity"]),
        countries: countries,
        categories_tags: string_list(product["categories_tags"]),
        nutriments: nutriments(product["nutriments"]),
        image_url: truncate(product["image_front_url"] || product["image_url"]),
        image_small_url: truncate(product["image_front_small_url"] || product["image_small_url"]),
        nutriscore_grade: truncate(product["nutriscore_grade"]),
        ecoscore_grade: truncate(product["ecoscore_grade"]),
        completeness: to_float(product["completeness"]),
        off_last_modified_t: to_int(product["last_modified_t"]),
        data_source: "open_food_facts"
      }

      {:ok, attrs, translations}
    end
  end

  @doc """
  Normalizes a barcode to canonical GTIN string form: digits only, leading
  zeros preserved, 12-digit UPC-A padded to GTIN-13.
  """
  def normalize_barcode(barcode) when is_binary(barcode) do
    barcode = String.trim(barcode)

    cond do
      not Regex.match?(@barcode_format, barcode) -> :skip
      String.length(barcode) == 12 -> {:ok, "0" <> barcode}
      true -> {:ok, barcode}
    end
  end

  def normalize_barcode(barcode) when is_integer(barcode),
    do: normalize_barcode(Integer.to_string(barcode))

  def normalize_barcode(_), do: :skip

  @doc "True when any of the product's country tags is a European market we import."
  def european?(countries_tags) when is_list(countries_tags) do
    Enum.any?(countries_tags, &MapSet.member?(@european_tags, &1))
  end

  def european_tags, do: @european_tags

  # ── private ──────────────────────────────────────────────────────────────────

  defp check_european(_countries, false), do: :ok

  defp check_european(countries, true) do
    if european?(countries), do: :ok, else: :skip
  end

  defp countries_tags(product) do
    product["countries_tags"] |> string_list() |> Enum.map(&String.downcase/1)
  end

  # product_name_<lang> / ingredients_text_<lang> keys, restricted to languages
  # that exist in the languages table. OFF keys are always lowercase, while
  # rows in `languages` may be capitalized (e.g. "En") — language_name keeps
  # the table's casing for the FK.
  defp extract_translations(product, known_languages) do
    known_languages
    |> Enum.map(fn lang ->
      off_lang = String.downcase(lang)
      name = non_empty(product["product_name_#{off_lang}"])
      ingredients_text = non_empty(product["ingredients_text_#{off_lang}"])

      %{language_name: lang, name: truncate(name), ingredients_text: ingredients_text}
    end)
    |> Enum.filter(& &1.name)
  end

  # Display name: OFF's primary product_name, else the English translation,
  # else any translation we kept. No name at all → skip (unusable row).
  defp pick_name(product, translations) do
    name =
      non_empty(product["product_name"]) ||
        case Enum.find(translations, &(String.downcase(&1.language_name) == "en")) ||
               List.first(translations) do
          %{name: name} -> name
          nil -> nil
        end

    if name, do: {:ok, name}, else: :skip
  end

  # Keep only the numeric nutriment values; OFF mixes in strings/units/serving keys.
  defp nutriments(nutriments) when is_map(nutriments) do
    nutriments
    |> Enum.filter(fn {key, value} -> is_binary(key) and is_number(value) end)
    |> Map.new()
  end

  defp nutriments(_), do: %{}

  defp string_list(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp string_list(_), do: []

  defp non_empty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_empty(_), do: nil

  defp truncate(nil), do: nil
  defp truncate(value) when is_binary(value), do: String.slice(value, 0, @string_limit)

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(_), do: nil

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_float(value), do: trunc(value)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_int(_), do: nil
end
