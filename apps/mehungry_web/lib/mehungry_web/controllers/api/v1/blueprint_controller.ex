defmodule MehungryWeb.Api.V1.BlueprintController do
  @moduledoc """
  Public meal-blueprint browse + detail for the mobile app. `index` lists public
  blueprints newest-first with optional `?q=` name search and page-based
  pagination; `show` returns one by slug with its full day/meal targets tree.

  Both endpoints are 🔓 — anonymous callers get the public catalogue, and a
  logged-in caller additionally gets a `saved` flag per blueprint.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.MealBlueprints
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.BlueprintJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    blueprints =
      case params["q"] do
        q when is_binary(q) and q != "" -> MealBlueprints.search_public_blueprints(q)
        _ -> MealBlueprints.list_public_blueprints()
      end

    saved_ids = saved_ids(conn.assigns[:current_user])
    {page, meta} = Pagination.paginate_list(blueprints, Pagination.params(params))
    meta = Map.put(meta, :total, length(blueprints))

    json(conn, data(Enum.map(page, &BlueprintJSON.summary(&1, saved_ids)), meta))
  end

  def show(conn, %{"slug" => slug}) do
    with {:ok, blueprint} <- fetch_public_blueprint(slug) do
      json(conn, BlueprintJSON.detail(blueprint, saved_ids(conn.assigns[:current_user])))
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp fetch_public_blueprint(slug) do
    {:ok, MealBlueprints.get_public_blueprint_by_slug!(slug)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp saved_ids(nil), do: []
  defp saved_ids(user), do: MealBlueprints.list_saved_blueprint_ids_for_user(user.id)
end
