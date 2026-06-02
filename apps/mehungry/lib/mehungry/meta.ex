defmodule Mehungry.Meta do
  @moduledoc """
  The Meta context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Meta.Visit

  @doc """
  Returns the list of visits.

  ## Examples

      iex> list_visits()
      [%Visit{}, ...]

  """
  def list_visits do
    from(vi in Visit,
      order_by: [desc: :inserted_at],
      distinct: vi.ip_address
    )
    |> Repo.all()
  end

  def list_visits(ip_address) do
    from(vi in Visit,
      where: vi.ip_address == ^ip_address,
      order_by: [desc: :inserted_at]
    )
    |> Repo.all()
  end

  def recent_visits(limit \\ 50) do
    from(v in Visit, order_by: [desc: v.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  def recent_visits_page(limit, offset) do
    from(v in Visit, order_by: [desc: v.inserted_at], limit: ^limit, offset: ^offset)
    |> Repo.all()
  end

  def distinct_referrers(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit,
      where:
        v.inserted_at >= ^cutoff and
          fragment("details->>'referrer'") != "" and
          not is_nil(fragment("details->>'referrer'")),
      group_by: fragment("details->>'referrer'"),
      select: fragment("details->>'referrer'")
    )
    |> Repo.all()
  end

  def top_pages(limit \\ 10) do
    from(v in Visit,
      where: not is_nil(fragment("details->>'path'")),
      group_by: fragment("details->>'path'"),
      select: %{path: fragment("details->>'path'"), count: count(v.id)},
      order_by: [desc: count(v.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def visits_per_day(days \\ 7) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit,
      where: v.inserted_at >= ^cutoff,
      group_by: fragment("DATE(inserted_at)"),
      select: %{date: fragment("DATE(inserted_at)"), count: count(v.id)},
      order_by: [asc: fragment("DATE(inserted_at)")]
    )
    |> Repo.all()
  end

  def stats_today do
    today_start = NaiveDateTime.new!(Date.utc_today(), ~T[00:00:00])

    %{
      total: Repo.one(from v in Visit, where: v.inserted_at >= ^today_start, select: count(v.id)),
      unique_ips:
        Repo.one(
          from v in Visit,
            where: v.inserted_at >= ^today_start,
            select: count(v.ip_address, :distinct)
        )
    }
  end

  def total_stats do
    %{
      total: Repo.one(from v in Visit, select: count(v.id)),
      unique_ips: Repo.one(from v in Visit, select: count(v.ip_address, :distinct))
    }
  end

  def traffic_sources(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit, where: v.inserted_at >= ^cutoff)
    |> Repo.all()
    |> Enum.group_by(fn v -> classify_referrer(Map.get(v.details || %{}, "referrer", "")) end)
    |> Enum.map(fn {source, visits} ->
      %{source: Atom.to_string(source), count: length(visits)}
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  def classify_referrer(nil), do: :direct
  def classify_referrer(""), do: :direct

  def classify_referrer(ref) do
    search =
      ~w[google. bing.com yahoo.com duckduckgo.com yandex. baidu.com ecosia.org search.brave.com ask.com]

    social =
      ~w[facebook.com twitter.com t.co instagram.com linkedin.com reddit.com pinterest.com tiktok.com youtube.com]

    cond do
      Enum.any?(search, &String.contains?(ref, &1)) -> :search
      Enum.any?(social, &String.contains?(ref, &1)) -> :social
      String.contains?(ref, "mehungry") -> :internal
      true -> :referral
    end
  end

  @doc """
  Gets a single visit.

  Raises `Ecto.NoResultsError` if the Visit does not exist.

  ## Examples

      iex> get_visit!(123)
      %Visit{}

      iex> get_visit!(456)
      ** (Ecto.NoResultsError)

  """
  def get_visit!(id), do: Repo.get!(Visit, id)

  @doc """
  Creates a visit.

  ## Examples

      iex> create_visit(%{field: value})
      {:ok, %Visit{}}

      iex> create_visit(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_visit(attrs \\ %{}) do
    %Visit{}
    |> Visit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a visit.

  ## Examples

      iex> update_visit(visit, %{field: new_value})
      {:ok, %Visit{}}

      iex> update_visit(visit, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_visit(%Visit{} = visit, attrs) do
    visit
    |> Visit.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a visit.

  ## Examples

      iex> delete_visit(visit)
      {:ok, %Visit{}}

      iex> delete_visit(visit)
      {:error, %Ecto.Changeset{}}

  """
  def delete_visit(%Visit{} = visit) do
    Repo.delete(visit)
  end

  def delete_all_visits() do
    Repo.delete_all(Visit)
  end

  def delete_all_visits(ip_address) do
    from(vi in Visit,
      where: vi.ip_address == ^ip_address
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking visit changes.

  ## Examples

      iex> change_visit(visit)
      %Ecto.Changeset{data: %Visit{}}

  """
  def change_visit(%Visit{} = visit, attrs \\ %{}) do
    Visit.changeset(visit, attrs)
  end

  # ---------- SEO analytics ----------

  def organic_visits_per_day(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit, where: v.inserted_at >= ^cutoff)
    |> Repo.all()
    |> Enum.filter(&organic?/1)
    |> Enum.group_by(fn v -> NaiveDateTime.to_date(v.inserted_at) end)
    |> Enum.map(fn {date, visits} -> %{date: date, count: length(visits)} end)
    |> Enum.sort_by(& &1.date)
  end

  def search_engine_breakdown(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit, where: v.inserted_at >= ^cutoff)
    |> Repo.all()
    |> Enum.filter(&organic?/1)
    |> Enum.group_by(fn v ->
      ref = get_in(v.details || %{}, ["referrer"]) || ""
      identify_search_engine(ref)
    end)
    |> Enum.map(fn {engine, visits} -> %{engine: engine, count: length(visits)} end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  def organic_landing_pages(days \\ 30, limit \\ 15) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit, where: v.inserted_at >= ^cutoff)
    |> Repo.all()
    |> Enum.filter(&organic?/1)
    |> Enum.group_by(fn v -> get_in(v.details || %{}, ["path"]) || "/" end)
    |> Enum.map(fn {path, visits} -> %{path: path, count: length(visits)} end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  def crawler_activity(days \\ 7) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit,
      where: v.inserted_at >= ^cutoff,
      order_by: [desc: v.inserted_at]
    )
    |> Repo.all()
    |> Enum.filter(fn v -> is_crawler?(get_in(v.details || %{}, ["agent"]) || "") end)
  end

  def search_queries_extracted(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit, where: v.inserted_at >= ^cutoff)
    |> Repo.all()
    |> Enum.filter(&organic?/1)
    |> Enum.flat_map(fn v ->
      ref = get_in(v.details || %{}, ["referrer"]) || ""

      case extract_search_query(ref) do
        nil -> []
        q -> [q]
      end
    end)
    |> Enum.group_by(& &1)
    |> Enum.map(fn {q, items} -> %{query: q, count: length(items)} end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(20)
  end

  def is_crawler?(agent) when is_nil(agent) or agent == "", do: false

  def is_crawler?(agent) do
    bots =
      ~w[Googlebot Bingbot DuckDuckBot YandexBot Yahoo! Slurp Baiduspider AhrefsBot SemrushBot facebookexternalhit Twitterbot Slackbot LinkedInBot]

    Enum.any?(bots, &String.contains?(agent, &1))
  end

  def crawler_name(agent) do
    cond do
      String.contains?(agent, "Googlebot") -> "Googlebot"
      String.contains?(agent, "Bingbot") or String.contains?(agent, "bingbot") -> "Bingbot"
      String.contains?(agent, "DuckDuckBot") -> "DuckDuckBot"
      String.contains?(agent, "YandexBot") -> "YandexBot"
      String.contains?(agent, "AhrefsBot") -> "AhrefsBot"
      String.contains?(agent, "SemrushBot") -> "SemrushBot"
      String.contains?(agent, "facebookexternalhit") -> "FacebookBot"
      String.contains?(agent, "Twitterbot") -> "Twitterbot"
      true -> "Other Bot"
    end
  end

  defp organic?(visit) do
    ref = get_in(visit.details || %{}, ["referrer"]) || ""
    classify_referrer(ref) == :search
  end

  defp identify_search_engine(ref) do
    cond do
      String.contains?(ref, "google.") -> "Google"
      String.contains?(ref, "bing.com") -> "Bing"
      String.contains?(ref, "duckduckgo.com") -> "DuckDuckGo"
      String.contains?(ref, "yahoo.com") -> "Yahoo"
      String.contains?(ref, "yandex.") -> "Yandex"
      String.contains?(ref, "baidu.com") -> "Baidu"
      String.contains?(ref, "ecosia.org") -> "Ecosia"
      String.contains?(ref, "brave.com") -> "Brave"
      true -> "Other"
    end
  end

  defp extract_search_query(ref) do
    case URI.parse(ref) do
      %URI{query: q} when not is_nil(q) ->
        params = URI.decode_query(q)
        params["q"] || params["query"] || params["p"] || params["wd"]

      _ ->
        nil
    end
  end
end
