defmodule MehungryWeb.Api.V1.MealController do
  @moduledoc """
  Calendar / meal planner (spec §9). Weekly range, single day, CRUD, consume,
  and daily nutrition. Backed by `Mehungry.History` + `History.MealType`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.History
  alias Mehungry.History.MealType
  alias Mehungry.MealPlanJobs
  alias Mehungry.NutrientUtils
  alias Mehungry.Subscriptions
  alias MehungryWeb.Api.MealPlanWorker
  alias MehungryWeb.Api.V1.Locale
  alias MehungryWeb.Api.V1.MealJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    with {:ok, start_date} <- parse_date(params["start"]),
         {:ok, end_date} <- parse_date(params["end"]) do
      meals = History.list_user_meals_in_range(uid(conn), start_date, end_date)
      json(conn, MealJSON.range(meals, start_date, end_date))
    end
  end

  def day(conn, %{"date" => date}) do
    meals = History.list_history_user_meals_for_user(uid(conn), date)
    json(conn, MealJSON.day(meals, date))
  end

  def create(conn, params) do
    with {:ok, attrs} <- meal_attrs(params, uid(conn)),
         {:ok, meal} <- History.create_user_meal(attrs) do
      conn |> put_status(:created) |> json(data(MealJSON.meal(reload(meal.id, uid(conn)))))
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, meal} <- fetch_meal(uid(conn), id),
         {:ok, attrs} <- meal_attrs(params, uid(conn), meal),
         {:ok, meal} <- History.update_user_meal(meal, attrs) do
      json(conn, data(MealJSON.meal(reload(meal.id, uid(conn)))))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, meal} <- fetch_meal(uid(conn), id),
         {:ok, _} <- History.delete_user_meal(meal) do
      send_resp(conn, :no_content, "")
    end
  end

  def consume(conn, %{"id" => id} = params) do
    with {:ok, _meal} <- fetch_meal(uid(conn), id),
         {:ok, meal} <- add_consume(uid(conn), id, params) do
      json(conn, data(MealJSON.meal(reload(meal.id, uid(conn)))))
    end
  end

  def nutrition(conn, %{"date" => date} = params) do
    summary =
      History.list_history_user_meals_for_user(uid(conn), date)
      |> History.format_user_meals()
      |> NutrientUtils.summarize_meals_nutrients()
      # Localize the nutrient names to the request locale — the same labels the
      # web calendar's daily breakdown shows (spec §Language).
      |> localize_nutrients(Locale.resolve(conn, params))

    json(conn, data(%{date: date, nutrition: summary}))
  end

  @doc """
  POST /api/v1/meals/plan-with-ai — quota-gated async generation. Returns 202 +
  job id; the client watches `meal_plan:<user_id>` or polls `plan_status`.
  """
  def plan_with_ai(conn, params) do
    user_id = uid(conn)

    case Subscriptions.check_quota(user_id, "meal_plan") do
      :ok ->
        {:ok, job} =
          MealPlanJobs.create_job(%{
            user_id: user_id,
            status: "queued",
            start_date: parse_optional_date(params["start"]),
            days: params["days"],
            notes: params["notes"]
          })

        %{"job_id" => job.id} |> MealPlanWorker.new() |> Oban.insert()

        conn |> put_status(:accepted) |> json(data(%{job_id: job.id, status: "queued"}))

      {:error, :quota_exceeded} ->
        {:error, :quota_exceeded}
    end
  end

  @doc "GET /api/v1/meals/plan-with-ai/:job_id — poll async generation status."
  def plan_status(conn, %{"job_id" => id}) do
    case MealPlanJobs.get_job(parse_int(id), uid(conn)) do
      nil -> {:error, :not_found}
      job -> json(conn, data(%{job_id: job.id, status: job.status, result: job.result, error: job.error}))
    end
  end

  # ── attrs ──────────────────────────────────────────────────────────────

  defp meal_attrs(params, user_id, existing \\ nil) do
    meal_type = Map.get(params, "meal_type", existing && existing.meal_type)

    with {:ok, start_dt} <- start_dt(params, meal_type, existing) do
      attrs =
        %{
          "user_id" => user_id,
          "meal_type" => meal_type,
          "title" => params["title"],
          "start_dt" => start_dt,
          "end_dt" => NaiveDateTime.add(start_dt, 1800, :second)
        }
        |> put_if(params, "recipe_user_meals", &recipe_user_meals/1)
        |> put_if(params, "ingredient_user_meals", &ingredient_user_meals/1)
        |> put_if(params, "free_food_user_meals", &free_food_user_meals/1)

      {:ok, attrs}
    end
  end

  defp start_dt(%{"date" => date} = _params, meal_type, _existing) when is_binary(date) do
    with {:ok, d} <- Date.from_iso8601(date) do
      {:ok, NaiveDateTime.new!(d, MealType.slot_time(meal_type))}
    else
      _ -> {:error, :bad_request}
    end
  end

  defp start_dt(_params, meal_type, %{start_dt: %NaiveDateTime{} = dt}) do
    {:ok, NaiveDateTime.new!(NaiveDateTime.to_date(dt), MealType.slot_time(meal_type))}
  end

  defp start_dt(_params, _meal_type, _existing), do: {:error, :bad_request}

  # Map the spec's `{recipe_id, servings}` onto the schema's required
  # consume_portions/cooking_portions.
  defp recipe_user_meals(list) when is_list(list) do
    Enum.map(list, fn rum ->
      servings = rum["servings"] || rum["consume_portions"] || 1

      %{
        "recipe_id" => rum["recipe_id"],
        "consume_portions" => servings,
        "cooking_portions" => rum["cooking_portions"] || servings
      }
    end)
  end

  # A logged ingredient resolves to a unit the same way the calendar form does:
  # the client may send the signed `unit_selection` (positive → measurement unit,
  # negative → `-ingredient_portion_id`) and let `IngredientUserMeal.changeset/2`
  # split it, or pass the resolved `measurement_unit_id` / `ingredient_portion_id`
  # FKs directly. Both are forwarded; a blank `unit_selection` is dropped by the
  # changeset so the explicit FKs win.
  defp ingredient_user_meals(list) when is_list(list) do
    Enum.map(list, fn ium ->
      %{
        "ingredient_id" => ium["ingredient_id"],
        "measurement_unit_id" => ium["measurement_unit_id"],
        "ingredient_portion_id" => ium["ingredient_portion_id"],
        "unit_selection" => ium["unit_selection"],
        "quantity" => ium["quantity"]
      }
    end)
  end

  # Arbitrary "free food" entries (fast food etc. not in our DB). The client is
  # the source of truth for the per-100g nutrition and the amount: either grams
  # directly, or portion_grams × portions. We resolve total grams here (the
  # scaling source of truth) and keep the portion metadata for display. Entries
  # with neither grams nor a portion pair resolve to nil grams and fail the
  # FreeFoodUserMeal changeset's `grams` required/positive check.
  defp free_food_user_meals(list) when is_list(list) do
    Enum.map(list, fn ff ->
      %{
        "name" => ff["name"],
        "grams" => resolve_grams(ff),
        "nutrients_per_100g" => normalize_per_100g(ff["nutrients_per_100g"]),
        "portion_name" => ff["portion_name"],
        "portion_grams" => ff["portion_grams"],
        "portions" => ff["portions"]
      }
    end)
  end

  # Grams mode wins when present; otherwise portion mode (portion_grams × portions).
  defp resolve_grams(%{"grams" => g}) when is_number(g), do: g

  defp resolve_grams(%{"portion_grams" => pg, "portions" => p})
       when is_number(pg) and is_number(p),
       do: pg * p

  defp resolve_grams(_), do: nil

  # Store the client's per-100g nutrients canonically as
  # %{"<name>" => %{"unit" => ..., "amount" => ...}} (the recipe.nutrients :map
  # convention) so the daily summary merges by nutrient name. Accepts the list
  # form `[{name,unit,amount}]` the client sends, or an already-canonical map.
  defp normalize_per_100g(list) when is_list(list) do
    for %{"name" => name} = n <- list, is_binary(name) and name != "", into: %{} do
      {name, %{"unit" => n["unit"], "amount" => n["amount"]}}
    end
  end

  defp normalize_per_100g(map) when is_map(map), do: map
  defp normalize_per_100g(_), do: %{}

  defp add_consume(user_id, id, params) do
    meal = History.get_user_meal_raw!(user_id, id)

    consume =
      (params["consume_recipe_user_meals"] || [params])
      |> Enum.map(fn c ->
        %{
          "recipe_user_meal_id" => c["recipe_user_meal_id"],
          "consume_portions" => c["portions"] || c["consume_portions"] || 1,
          "start_dt" => meal.start_dt,
          "end_dt" => meal.end_dt
        }
      end)
      |> Enum.reject(&is_nil(&1["recipe_user_meal_id"]))

    History.update_user_meal(meal, %{"consume_recipe_user_meals" => consume})
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp fetch_meal(user_id, id) do
    {:ok, History.get_user_meal_raw!(user_id, id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp reload(id, user_id) do
    [start_date, end_date] = day_bounds(id, user_id)
    History.list_user_meals_in_range(user_id, start_date, end_date) |> Enum.find(&(&1.id == id))
  end

  defp day_bounds(id, user_id) do
    meal = History.get_user_meal!(user_id, id)
    date = NaiveDateTime.to_date(meal.start_dt)
    [date, date]
  end

  defp parse_date(nil), do: {:error, :bad_request}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, :bad_request}
    end
  end

  defp parse_optional_date(nil), do: nil

  defp parse_optional_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_int(v) when is_integer(v), do: v
  defp parse_int(v) when is_binary(v), do: String.to_integer(v)

  defp put_if(attrs, params, key, fun) do
    case Map.fetch(params, key) do
      {:ok, value} when is_list(value) -> Map.put(attrs, key, fun.(value))
      _ -> attrs
    end
  end

  defp uid(conn), do: conn.assigns.current_user.id
end
