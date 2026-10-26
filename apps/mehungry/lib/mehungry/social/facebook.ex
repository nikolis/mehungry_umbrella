defmodule Mehungry.Social.Facebook do
  require Logger

  alias Mehungry.Food.Recipe

  @api_base "https://graph.facebook.com/"
  @api_version "v21.0"
  @timeout_ms 15_000

  @priority_nutrients [
    "Energy",
    "Protein",
    "Total Fat",
    "Total Carbohydrate",
    "Carbohydrate",
    "Dietary Fiber",
    "Fiber",
    "Sodium"
  ]

  @doc """
  Fetch the user's Facebook page list and store it on the user's tokens.

  Returns `{:ok, user} | {:error, {:http_error, status, body}} |
  {:error, {:transport_error, reason}} | {:error, {:invalid_json, reason}}`.
  """
  def get_user_pages(user, token, facebook_user_id) do
    url = @api_base <> @api_version <> "/" <> facebook_user_id <> "/accounts"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/json"}
    ]

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get(url, headers, recv_timeout: @timeout_ms),
         {:ok, decoded} <- Jason.decode(body) do
      pages =
        Enum.reduce(decoded["data"] || [], %{}, fn page, acc ->
          Map.put(acc, page["name"], page)
        end)

      Mehungry.Accounts.update_user_tokens(user, %{"facebook_token" => pages})
    else
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.warning("[Facebook] page fetch failed with HTTP #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("[Facebook] page fetch transport error: #{inspect(reason)}")
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        Logger.warning("[Facebook] page fetch returned invalid JSON: #{inspect(reason)}")
        {:error, {:invalid_json, reason}}
    end
  end

  @doc """
  Post the recipe as a photo to the given Facebook page.
  Uses recipe.image_url as the photo and a formatted caption with
  ingredients and key nutrients.

  Returns `{:ok, decoded_body} | {:error, {:http_error, status, body}} |
  {:error, {:transport_error, reason}}`.
  """
  def post_recipe_container(_user, recipe, page) do
    user_id = Map.get(page, "id", "")
    access_token = Map.get(page, "access_token", "")
    caption = build_caption(recipe)

    response =
      HTTPoison.post(
        @api_base <> @api_version <> "/" <> user_id <> "/photos",
        "",
        [{"Accept", "application/json"}],
        params: %{
          url: recipe.image_url,
          caption: caption,
          published: true,
          access_token: access_token
        },
        timeout: @timeout_ms,
        recv_timeout: @timeout_ms
      )

    case response do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:ok, body}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  # Each queried on its own: the Graph API rejects the *entire* request (error
  # #100) if any one metric in a comma list is invalid, and Meta deprecates
  # these between versions — so a single stale name must not nuke the rest.
  # `{report key, graph metric name}`.
  @insight_metrics [
    {:reach_28d, "page_impressions_unique"},
    {:impressions_28d, "page_impressions"},
    {:engagements_28d, "page_post_engagements"}
  ]

  @doc """
  Page reach/engagement insights (§7.3 of `docs/implementation/app_status.md`) for every
  Facebook Page stored on the user's `facebook_token`, using each Page's own
  access token. Returns `{:ok, [page_summary]}` with one map per page:

      %{name:, id:, followers:, fans:, reach_28d:, impressions_28d:,
        engagements_28d:, insights_note: (set only when no metric resolved)}

  or `{:error, :not_connected}` when no pages are stored.

  Follower counts come from the Page fields (need `pages_read_engagement`); the
  28-day metrics come from the insights edge (need `read_insights`). Each metric
  is fetched independently and simply omitted (left `nil`) if that name is
  invalid in the current Graph API version, so the report degrades per-metric
  instead of failing wholesale.
  """
  def page_insights(user) do
    pages = Map.values(user.facebook_token || %{})

    case pages do
      [] -> {:error, :not_connected}
      pages -> {:ok, Enum.map(pages, &page_summary/1)}
    end
  end

  defp page_summary(page) do
    id = Map.get(page, "id", "")
    token = Map.get(page, "access_token", "")
    base = %{name: Map.get(page, "name"), id: id}

    base
    |> Map.merge(page_fields(id, token))
    |> Map.merge(page_insight_metrics(id, token))
  end

  defp page_fields(id, token) do
    case graph_get("/#{id}", token, %{"fields" => "followers_count,fan_count"}) do
      {:ok, body} ->
        %{followers: body["followers_count"], fans: body["fan_count"]}

      {:error, reason} ->
        %{followers: nil, fans: nil, error: reason}
    end
  end

  defp page_insight_metrics(id, token) do
    results = Enum.map(@insight_metrics, fn {key, metric} -> {key, fetch_metric(id, token, metric)} end)

    values = for {key, {:ok, v}} <- results, into: %{}, do: {key, v}
    last_error = Enum.find_value(results, fn {_k, r} -> match?({:error, _}, r) && elem(r, 1) end)

    @insight_metrics
    |> Enum.map(fn {key, _} -> {key, Map.get(values, key)} end)
    |> Map.new()
    |> maybe_note(map_size(values), last_error)
  end

  # Only surface a note when *nothing* resolved — one deprecated name among
  # several that still work shouldn't look like a failure.
  defp maybe_note(metrics, 0, error) when not is_nil(error),
    do: Map.put(metrics, :insights_note, error)

  defp maybe_note(metrics, _resolved, _error), do: metrics

  defp fetch_metric(id, token, metric) do
    case graph_get("/#{id}/insights", token, %{"metric" => metric, "period" => "days_28"}) do
      {:ok, %{"data" => [%{"values" => values} | _]}} ->
        {:ok, values |> List.last() |> then(&(&1 && &1["value"]))}

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp graph_get(path, token, params) do
    url = @api_base <> @api_version <> path

    headers = [{"Accept", "application/json"}]
    opts = [params: Map.put(params, "access_token", token), recv_timeout: @timeout_ms]

    case HTTPoison.get(url, headers, opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "HTTP #{status}: #{String.slice(body, 0, 300)}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Caption builder
  # ---------------------------------------------------------------------------

  defp build_caption(%Recipe{} = recipe) do
    [
      header(recipe),
      ingredients_section(recipe),
      nutrients_section(recipe),
      footer(recipe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp header(%Recipe{title: title, description: desc}) do
    base = "🍽️  #{title}"

    if desc && String.trim(desc) != "" do
      base <> "\n" <> String.trim(desc)
    else
      base
    end
  end

  defp ingredients_section(%Recipe{recipe_ingredients: %Ecto.Association.NotLoaded{}}), do: nil
  defp ingredients_section(%Recipe{recipe_ingredients: []}), do: nil

  defp ingredients_section(%Recipe{recipe_ingredients: items, servings: servings}) do
    label =
      if servings && servings > 0,
        do: "📋  Ingredients  (#{servings} servings)",
        else: "📋  Ingredients"

    lines =
      items
      |> Enum.reject(fn ri ->
        is_struct(ri.ingredient, Ecto.Association.NotLoaded) or
          is_struct(ri.measurement_unit, Ecto.Association.NotLoaded)
      end)
      |> Enum.map(fn ri ->
        qty = format_qty(ri.quantity)
        "  • #{qty} #{Mehungry.Food.RecipeIngredient.unit_label(ri)}  #{ri.ingredient.name}"
      end)

    if lines == [] do
      nil
    else
      label <> "\n" <> Enum.join(lines, "\n")
    end
  end

  defp nutrients_section(%Recipe{nutrients: nutrients, servings: servings})
       when is_map(nutrients) and map_size(nutrients) > 0 do
    per = if servings && servings > 0, do: servings, else: 1

    lines =
      nutrients
      |> Map.values()
      |> Enum.filter(fn n ->
        name = n["name"] || ""
        Enum.any?(@priority_nutrients, &(String.downcase(name) == String.downcase(&1)))
      end)
      |> Enum.sort_by(fn n ->
        name = n["name"] || ""

        Enum.find_index(@priority_nutrients, &(String.downcase(name) == String.downcase(&1))) ||
          99
      end)
      |> Enum.map(fn n ->
        name = n["name"] || ""
        amount = (n["amount"] || 0) / per
        unit = n["measurement_unit"] || "g"
        "  • #{name}: #{format_amount(amount)} #{unit}"
      end)

    if lines == [] do
      nil
    else
      "📊  Nutrition per serving\n" <> Enum.join(lines, "\n")
    end
  end

  defp nutrients_section(_), do: nil

  defp footer(%Recipe{id: id}) do
    "🔗  https://www.m3hungry.com/browse/#{id}\n#m3hungry #recipe"
  end

  defp format_qty(qty) when is_float(qty) do
    if qty == Float.round(qty, 0),
      do: trunc(qty) |> to_string(),
      else: Float.round(qty, 1) |> to_string()
  end

  defp format_qty(qty), do: to_string(qty)

  defp format_amount(amount) when is_float(amount) do
    cond do
      amount >= 100 -> trunc(Float.round(amount, 0)) |> to_string()
      amount >= 10 -> Float.round(amount, 1) |> to_string()
      amount >= 1 -> Float.round(amount, 2) |> to_string()
      true -> Float.round(amount, 3) |> to_string()
    end
  end
end
