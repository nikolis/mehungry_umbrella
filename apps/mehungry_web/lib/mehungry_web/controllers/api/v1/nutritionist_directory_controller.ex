defmodule MehungryWeb.Api.V1.NutritionistDirectoryController do
  @moduledoc """
  Public nutritionist discovery (spec §18) — the directory, a public profile, its
  open booking slots, and its published articles. Mirrors
  `PublicNutritionistLive.{Index, Show, Article}`; all reads delegate to
  `Mehungry.Professionals`. These endpoints are 🔓 (optional auth); nothing is
  pro-gated.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.NutritionistJSON, as: JSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    filters = Map.take(params, ["city", "q"])
    all = Professionals.list_public_professionals(filters)
    {page, meta} = Pagination.paginate_list(all, Pagination.params(params))

    body =
      data(Enum.map(page, &JSON.directory_entry/1), meta)
      |> Map.put(:cities, Professionals.list_professional_cities())

    json(conn, body)
  end

  def show(conn, %{"slug" => slug}) do
    with {:ok, profile} <- fetch_profile(slug) do
      json(conn, data(JSON.profile(profile, services(profile), articles(profile), payments_enabled?(profile))))
    end
  end

  def slots(conn, %{"slug" => slug} = params) do
    with {:ok, profile} <- fetch_profile(slug) do
      from = parse_date(params["from"]) || Date.utc_today()
      to = parse_date(params["to"]) || Date.add(Date.utc_today(), 30)
      open = Professionals.available_slots(profile.user_id, from, to)
      json(conn, data(JSON.slots(profile, services(profile), open)))
    end
  end

  def articles(conn, %{"slug" => slug}) do
    with {:ok, profile} <- fetch_profile(slug) do
      json(conn, data(Enum.map(articles(profile), &JSON.article_summary/1)))
    end
  end

  def article(conn, %{"slug" => slug, "article_slug" => article_slug}) do
    with %{} = article <- Professionals.get_published_article_by_slug(article_slug),
         true <- article.professional_profile && article.professional_profile.slug == slug do
      json(conn, data(JSON.article(article)))
    else
      _ -> {:error, :not_found}
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp fetch_profile(slug) do
    case Professionals.get_public_professional_by_slug(slug) do
      %ProfessionalProfile{} = profile -> {:ok, profile}
      nil -> {:error, :not_found}
    end
  end

  # Services are keyed on the professional's user id; articles on the profile id.
  defp services(profile), do: Professionals.list_active_services(profile.user_id)
  defp articles(profile), do: Professionals.list_published_articles_for_profile(profile.id)

  defp payments_enabled?(profile),
    do: Professionals.consultation_payments_enabled?() and ProfessionalProfile.payable?(profile)

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
