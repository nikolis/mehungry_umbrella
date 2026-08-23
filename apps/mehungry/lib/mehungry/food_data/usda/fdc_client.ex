defmodule Mehungry.FoodData.Usda.FdcClient do
  @moduledoc """
  HTTP client for the USDA FoodData Central (FDC) API.

  Searches for an ingredient by name (SR Legacy → Foundation data priority),
  fetches full nutrient detail, and returns a JSON string in the same format
  that FoodParser.get_ingredients_from_json_body/1 expects.

  Set FDC_API_KEY in the environment. Free API keys:
  https://api.nal.usda.gov/api-key-signup
  """

  require Logger

  alias Mehungry.FoodData.Usda.FdcHttp

  @base_url "https://api.nal.usda.gov/fdc/v1"

  # The public API serves food detail from a store that is missing a large class
  # of Foundation Foods records (e.g. fdcId 333281) — `/food/{id}` returns 404
  # for them even though they are present in the API's own search index and on
  # the website. The website's backend datastore still has the full record, so
  # `fetch_food/1` falls back here on a 404. Undocumented/internal endpoint;
  # different JSON shape (see `portal_to_parser_format/1`).
  @portal_url "https://fdc.nal.usda.gov/portal-data/external"
  @timeout_ms 15_000

  @doc """
  Looks up an ingredient by name in the USDA FDC database.

  Returns `{:ok, json_string}` where json_string is a single-element JSON array
  in the FoodParser-compatible format, or `{:error, reason}` if the lookup
  fails (caller should fall back to AI estimation). A rate-limited lookup
  returns `{:error, {:rate_limited, retry_after_seconds}}`.
  """
  def lookup(name) do
    with {:ok, key} <- require_key(),
         {:ok, fdc_id, description} <- search(name, key),
         {:ok, attrs, _meta} <- fetch_parser_format(fdc_id, key) do
      Logger.info("[FdcClient] Matched '#{description}' (fdcId=#{fdc_id}) for '#{name}'")
      {:ok, attrs |> List.wrap() |> Jason.encode!()}
    end
  end

  @doc """
  Fetches a single food by its already-known FDC id (the `/food/{fdcId}`
  endpoint) and returns it in the nested-map format
  `FoodParser.reconcile_ingredient/2` expects.

  Unlike `lookup/1`, this skips the name search entirely — the caller already
  holds the authoritative `fdcId` (e.g. an ingredient row being reconciled), so
  there is no ambiguity to resolve.

  Returns `{:ok, food_attrs, meta}` where `meta` is `%{remaining: n | nil}`
  carrying the API's `x-ratelimit-remaining` (nil for portal-recovered records),
  `{:error, {:rate_limited, retry_after_seconds}}` when the API is rate-limiting,
  or `{:error, reason}` for other failures.
  """
  def fetch_food(fdc_id) do
    with {:ok, key} <- require_key() do
      fetch_parser_format(fdc_id, key)
    end
  end

  # Exposed for the fixture regression test in `fdc_client_test.exs`: the portal
  # endpoint is undocumented, so the test pins the adapter's shape against a
  # captured sample. Not part of the public API.
  @doc false
  def adapt_portal_food(portal_json), do: portal_to_parser_format(portal_json)

  @doc """
  Resolves a bare USDA NDB number (e.g. `"10205"`) to its real food description.

  The FDC API has no direct by-NDB endpoint, so this searches the SR Legacy
  dataset (which carries `ndbNumber`) for the number and returns the description
  of the row whose `ndbNumber` matches exactly.

  Returns `{:ok, %{name: description, fdc_id: id, ndb_number: ndb}, meta}`,
  `{:error, :no_ndb_match}` when nothing matches, `{:error, {:rate_limited, secs}}`
  when throttled, or `{:error, reason}` for other failures.
  """
  def lookup_name_by_ndb_number(ndb_number) when is_binary(ndb_number) do
    with {:ok, key} <- require_key() do
      params =
        URI.encode_query(%{
          query: ndb_number,
          dataType: "SR Legacy",
          pageSize: 50,
          api_key: key
        })

      case FdcHttp.get("#{@base_url}/foods/search?#{params}") do
        {:ok, %{"foods" => foods}, meta} when is_list(foods) ->
          case Enum.find(foods, fn f -> to_string(f["ndbNumber"]) == ndb_number end) do
            %{"description" => desc} = food ->
              {:ok, %{name: desc, fdc_id: food["fdcId"], ndb_number: ndb_number}, meta}

            _ ->
              {:error, :no_ndb_match}
          end

        {:ok, _other, _meta} ->
          {:error, :unexpected_response}

        {:error, _} = err ->
          err
      end
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp require_key do
    case api_key() do
      key when key in [nil, ""] -> {:error, "FDC_API_KEY not configured"}
      key -> {:ok, key}
    end
  end

  # Fetch the detail record and map it into parser format, transparently
  # recovering Foundation foods the public API 404s on from the website's own
  # datastore. Returns `{:ok, attrs, meta}` or a structured `{:error, _}`.
  defp fetch_parser_format(fdc_id, key) do
    case FdcHttp.get("#{@base_url}/food/#{fdc_id}?api_key=#{key}") do
      {:ok, food, meta} ->
        {:ok, to_parser_format(food), meta}

      # Foundation foods the public detail API doesn't serve (404) are still
      # available from the website's own datastore — recover them there.
      {:error, :not_found} ->
        fetch_food_from_portal(fdc_id)

      {:error, _} = err ->
        err
    end
  end

  defp search(name, key) do
    params =
      URI.encode_query(%{
        query: name,
        dataType: "SR Legacy,Foundation",
        pageSize: 1,
        api_key: key
      })

    case FdcHttp.get("#{@base_url}/foods/search?#{params}") do
      {:ok, %{"foods" => [%{"fdcId" => fdc_id, "description" => desc} | _]}, _meta} ->
        {:ok, fdc_id, desc}

      {:ok, %{"foods" => []}, _meta} ->
        {:error, "no FDC results for '#{name}'"}

      {:ok, _other, _meta} ->
        {:error, "unexpected FDC search response shape"}

      {:error, _} = err ->
        err
    end
  end

  # Fallback for Foundation foods the public detail API 404s on. Hits the
  # website's own backend (`/portal-data/external/{fdcId}`), which carries the
  # complete record keyed by exactly the fdcId we already hold — no name search,
  # no ambiguity. The JSON shape differs from the public API, so it gets its own
  # adapter rather than reusing `to_parser_format/1`.
  defp fetch_food_from_portal(fdc_id) do
    url = "#{@portal_url}/#{fdc_id}"

    case HTTPoison.get(url, [], recv_timeout: @timeout_ms) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, food} ->
            Logger.info(
              "[FdcClient] Recovered fdcId=#{fdc_id} via portal-data (public detail API 404)"
            )

            # Portal is a separate, unmetered host, so there is no rate-limit
            # metadata to report.
            {:ok, portal_to_parser_format(food), %{remaining: nil}}

          {:error, reason} ->
            {:error, "FDC portal JSON parse error: #{inspect(reason)}"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "FDC portal HTTP #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "FDC portal network error: #{inspect(reason)}"}
    end
  end

  # Converts the FDC API /food/{fdcId} response to the nested-map format expected
  # by FoodParser.create_ingredient/1.
  defp to_parser_format(food) do
    %{
      "description" => food["description"],
      # dataType ("Foundation" | "SR Legacy" | "Branded" | "Survey (FNDDS)") is the
      # real dataset discriminator; foodClass is an internal field that is almost
      # always "FinalFood". Carry both so the parser can prefer dataType.
      "dataType" => food["dataType"],
      "foodClass" => food["foodClass"] || "FinalFood",
      # USDA source keys carried onto the ingredient row for reconciliation.
      "fdcId" => food["fdcId"],
      "ndbNumber" => food["ndbNumber"],
      "publicationDate" => food["publicationDate"] || "4/1/2019",
      "nutrientConversionFactors" => food["nutrientConversionFactors"] || [],
      "foodCategory" => normalize_category(food["foodCategory"]),
      "foodPortions" => normalize_portions(food["foodPortions"] || []),
      "foodNutrients" => normalize_nutrients(food["foodNutrients"] || [])
    }
  end

  # Converts the website portal-data response to the same nested-map format
  # `to_parser_format/1` produces. The portal record uses different field names
  # than the public API: `foodType` instead of `dataType`, `foodGroup` instead
  # of `foodCategory`, `lastUpdated` instead of `publicationDate`, `foodMeasures`
  # instead of `foodPortions`, and each nutrient's value lives in `"value"`
  # (not `"amount"`) with the unit under `nutrient.nutrientUnit.name`.
  defp portal_to_parser_format(food) do
    %{
      "description" => food["description"],
      "dataType" => food["dataType"] || food["foodType"],
      "foodClass" => food["foodClass"] || "FinalFood",
      "fdcId" => food["fdcId"],
      "ndbNumber" => food["ndbNumber"],
      "publicationDate" => food["publicationDate"] || food["lastUpdated"] || "4/1/2019",
      "nutrientConversionFactors" => food["nutrientConversionFactors"] || [],
      "foodCategory" => normalize_category(food["foodCategory"] || food["foodGroup"]),
      "foodPortions" => normalize_portal_measures(food["foodMeasures"] || []),
      "foodNutrients" => normalize_portal_nutrients(food["foodNutrients"] || [])
    }
  end

  defp normalize_portal_measures(measures) do
    measures
    |> Enum.with_index(1)
    |> Enum.map(fn {m, i} ->
      gram_weight = m["gramWeight"] || 100.0
      amount = m["value"] || 1.0
      unit = portal_measure_unit(m)

      modifier =
        case m["modifier"] do
          mod when is_binary(mod) and mod != "" -> mod
          _ -> unit || "serving"
        end

      %{
        "modifier" => modifier,
        "gramWeight" => gram_weight,
        "amount" => amount,
        "value" => gram_weight,
        "id" => m["id"] || i,
        "sequenceNumber" => i,
        "minYearAcquired" => m["minYearAcquired"]
      }
    end)
  end

  defp normalize_portal_nutrients(nutrients) do
    nutrients
    |> Enum.filter(fn n ->
      nut = n["nutrient"]

      is_map(nut) and not is_nil(nut["id"]) and nut["isNutrientLabel"] != true and
        not is_nil(n["value"])
    end)
    |> Enum.map(fn n ->
      nut = n["nutrient"]

      %{
        "amount" => n["value"] || 0.0,
        "median" => n["median"],
        "dataPoints" => n["dataPoints"],
        "type" => "FoodNutrient",
        "nutrient" => %{
          "id" => nut["id"],
          "name" => nut["name"],
          "number" => to_string(nut["number"] || ""),
          "rank" => nut["rank"] || 0,
          "unitName" => normalize_unit(portal_unit_name(nut))
        }
      }
    end)
  end

  # Portal measures with an "undetermined" unit carry no usable name — treat it
  # as absent so the caller falls back to the modifier text or "serving".
  defp portal_measure_unit(%{"measureUnit" => %{"name" => name}})
       when is_binary(name) and name not in ["", "undetermined"],
       do: name

  defp portal_measure_unit(_), do: nil

  defp portal_unit_name(%{"nutrientUnit" => %{"name" => name}}) when is_binary(name), do: name
  defp portal_unit_name(_), do: nil

  defp normalize_category(nil), do: %{"description" => "General"}
  defp normalize_category(cat) when is_binary(cat), do: %{"description" => cat}
  defp normalize_category(%{"description" => desc}), do: %{"description" => desc || "General"}
  defp normalize_category(_), do: %{"description" => "General"}

  defp normalize_portions(portions) do
    portions
    |> Enum.with_index(1)
    |> Enum.map(fn {p, i} ->
      gram_weight = p["gramWeight"] || 100.0
      amount = p["amount"] || 1.0
      modifier = p["modifier"] || extract_unit(p["portionDescription"]) || "serving"

      %{
        "modifier" => modifier,
        "gramWeight" => gram_weight,
        "amount" => amount,
        "value" => gram_weight,
        "id" => p["id"] || i,
        "sequenceNumber" => p["sequenceNumber"] || i,
        "minYearAcquired" => p["minYearAcquired"]
      }
    end)
  end

  defp normalize_nutrients(nutrients) do
    nutrients
    |> Enum.filter(fn n -> is_map(n["nutrient"]) and not is_nil(n["nutrient"]["id"]) end)
    |> Enum.map(fn n ->
      nut = n["nutrient"]

      %{
        "amount" => n["amount"] || 0.0,
        "median" => n["median"],
        "dataPoints" => n["dataPoints"],
        "type" => "FoodNutrient",
        "nutrient" => %{
          "id" => nut["id"],
          "name" => nut["name"],
          "number" => to_string(nut["number"] || ""),
          "rank" => nut["rank"] || 0,
          "unitName" => normalize_unit(nut["unitName"])
        }
      }
    end)
  end

  defp normalize_unit(nil), do: "g"
  defp normalize_unit("G"), do: "g"
  defp normalize_unit("MG"), do: "mg"
  defp normalize_unit("UG"), do: "µg"
  defp normalize_unit("KCAL"), do: "kcal"
  defp normalize_unit("KJ"), do: "kJ"
  defp normalize_unit(u), do: String.downcase(u)

  # Best-effort unit extraction from a portion description like "1 cup, whole"
  defp extract_unit(nil), do: nil

  defp extract_unit(desc) do
    desc
    |> String.split(~r/[\s,]+/)
    |> Enum.find(fn word -> String.length(word) > 1 and Regex.match?(~r/^[a-zA-Z]+$/, word) end)
  end

  defp api_key do
    Application.get_env(:mehungry, :fdc_api_key, "")
  end
end
