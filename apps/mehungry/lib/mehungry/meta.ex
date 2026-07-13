defmodule Mehungry.Meta do
  @moduledoc """
  The Meta context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Meta.Visit

  @doc """
  IANA timezone the analytics dashboard reports in, so its day boundaries and
  daily buckets match the Google Analytics property timezone instead of UTC.
  """
  def reporting_timezone do
    Application.get_env(:mehungry, :reporting_timezone, "Etc/UTC")
  end

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
    tz = reporting_timezone()
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    # Bucket by local calendar date in the reporting timezone (Postgres carries
    # its own tz database, so no Elixir tz dependency is needed in this app).
    from(v in Visit,
      where: v.inserted_at >= ^cutoff,
      select: %{
        date:
          selected_as(
            fragment("DATE(? AT TIME ZONE 'UTC' AT TIME ZONE ?)", v.inserted_at, ^tz),
            :local_date
          ),
        count: count(v.id)
      },
      group_by: selected_as(:local_date),
      order_by: selected_as(:local_date)
    )
    |> Repo.all()
  end

  @doc """
  Today's counts in the reporting timezone. `total` is page views (one row per
  tracked mount/navigation ≈ GA "Views"), `users` is distinct visitor cookies
  (≈ GA "Users"), `unique_ips` is kept for reference.
  """
  def stats_today do
    tz = reporting_timezone()

    # A row belongs to "today" when its local calendar date equals the current
    # local calendar date — both computed in the reporting timezone.
    today =
      from v in Visit,
        where:
          fragment("DATE(? AT TIME ZONE 'UTC' AT TIME ZONE ?)", v.inserted_at, ^tz) ==
            fragment("(now() AT TIME ZONE ?)::date", ^tz)

    %{
      total: Repo.one(from(v in today, select: count(v.id))),
      unique_ips: Repo.one(from(v in today, select: count(v.ip_address, :distinct))),
      users:
        Repo.one(
          from v in today,
            select: count(fragment("?->>'visitor_id'", v.details), :distinct)
        )
    }
  end

  def total_stats do
    %{
      total: Repo.one(from v in Visit, select: count(v.id)),
      unique_ips: Repo.one(from v in Visit, select: count(v.ip_address, :distinct)),
      users:
        Repo.one(
          from v in Visit, select: count(fragment("?->>'visitor_id'", v.details), :distinct)
        )
    }
  end

  def traffic_sources(days \\ 30) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)

    from(v in Visit,
      where: v.inserted_at >= ^cutoff,
      group_by: fragment("COALESCE(details->>'referrer', '')"),
      select: {fragment("COALESCE(details->>'referrer', '')"), count(v.id)}
    )
    |> Repo.all()
    |> Enum.group_by(fn {referrer, _count} -> classify_referrer(referrer) end)
    |> Enum.map(fn {source, referrers} ->
      %{
        source: Atom.to_string(source),
        count: referrers |> Enum.map(fn {_referrer, count} -> count end) |> Enum.sum()
      }
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
    result =
      %Visit{}
      |> Visit.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, visit} ->
        Task.Supervisor.start_child(Mehungry.TaskSupervisor, fn ->
          enrich_visit_country(visit)
        end)

        result

      _ ->
        result
    end
  end

  defp enrich_visit_country(visit) do
    ip = visit.ip_address

    if ip && ip != "" && !local_ip?(ip) do
      country =
        case Cachex.get(:geo_cache, ip) do
          {:ok, nil} ->
            resolved = fetch_country(ip)
            Cachex.put(:geo_cache, ip, resolved)
            resolved

          {:ok, cached} ->
            cached

          _ ->
            nil
        end

      if country do
        update_visit(visit, %{details: Map.put(visit.details || %{}, "country", country)})
      end
    end
  end

  defp local_ip?(ip) do
    String.starts_with?(ip, [
      "127.",
      "192.168.",
      "10.",
      "172.16.",
      "172.17.",
      "172.18.",
      "172.19.",
      "172.20.",
      "172.21.",
      "172.22.",
      "172.23.",
      "172.24.",
      "172.25.",
      "172.26.",
      "172.27.",
      "172.28.",
      "172.29.",
      "172.30.",
      "172.31.",
      "::1"
    ])
  end

  defp fetch_country(ip) do
    url = "http://ip-api.com/json/#{ip}?fields=country,countryCode"

    case HTTPoison.get(url, [], recv_timeout: 3_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"status" => "success", "country" => country, "countryCode" => code}} ->
            "#{country} (#{code})"

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Updates a visit.

  ## Examples

      iex> update_visit(visit, %{field: new_value})
      {:ok, %Visit{}}

      iex> update_visit(visit, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_visit_timing(visit_id, ttfb_ms, load_ms) do
    case Repo.get(Visit, visit_id) do
      nil ->
        :ok

      visit ->
        details = Map.merge(visit.details || %{}, %{"ttfb_ms" => ttfb_ms, "load_ms" => load_ms})
        update_visit(visit, %{details: details})
    end
  end

  def update_visit_recipe_timing(visit_id, elapsed_ms, server_ms, recipe_id) do
    case Repo.get(Visit, visit_id) do
      nil ->
        :ok

      visit ->
        entry = %{
          "elapsed_ms" => elapsed_ms,
          "server_ms" => server_ms,
          "recipe_id" => recipe_id,
          "at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        timings =
          (visit.details || %{})
          |> Map.get("recipe_detail_timings", [])
          |> then(&[entry | &1])
          |> Enum.take(20)

        details = Map.merge(visit.details || %{}, %{"recipe_detail_timings" => timings})
        update_visit(visit, %{details: details})
    end
  end

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

  @session_gap_sec 1800

  def recent_sessions(limit \\ 30, days \\ 7) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -(days * 86_400), :second)
    raw_limit = limit * 12

    from(v in Visit,
      where: v.inserted_at >= ^cutoff,
      order_by: [desc: v.inserted_at],
      limit: ^raw_limit
    )
    |> Repo.all()
    |> Enum.sort_by(& &1.inserted_at)
    |> group_into_sessions()
    |> Enum.sort_by(& &1.started_at, {:desc, NaiveDateTime})
    |> Enum.take(limit)
  end

  def user_sessions(user_id) do
    id_str = to_string(user_id)

    visitor_ids =
      from(v in Visit,
        where: fragment("details->>'user_id'") == ^id_str,
        select: fragment("details->>'visitor_id'"),
        distinct: true
      )
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    query =
      if visitor_ids == [] do
        from(v in Visit,
          where: fragment("details->>'user_id'") == ^id_str,
          order_by: [asc: v.inserted_at]
        )
      else
        from(v in Visit,
          where:
            fragment("details->>'user_id'") == ^id_str or
              fragment("details->>'visitor_id'") in ^visitor_ids,
          order_by: [asc: v.inserted_at]
        )
      end

    query
    |> Repo.all()
    |> group_into_sessions()
    |> Enum.sort_by(& &1.started_at, {:desc, NaiveDateTime})
  end

  defp group_into_sessions(visits) do
    visits
    |> Enum.group_by(&session_identifier/1)
    |> Enum.flat_map(fn {_key, group} ->
      group
      |> Enum.sort_by(& &1.inserted_at)
      |> split_by_time_gap()
    end)
  end

  defp session_identifier(visit) do
    visitor_id = get_in(visit.details || %{}, ["visitor_id"])

    cond do
      visitor_id && visitor_id != "" ->
        "v:#{visitor_id}"

      visit.session_key && visit.session_key != "" ->
        visit.session_key

      true ->
        ip = visit.ip_address || ""
        agent = get_in(visit.details || %{}, ["agent"]) || ""
        date = NaiveDateTime.to_date(visit.inserted_at) |> Date.to_string()

        :crypto.hash(:sha256, "#{ip}|#{agent}|#{date}")
        |> Base.encode16(case: :lower)
        |> String.slice(0, 24)
    end
  end

  defp split_by_time_gap(visits) do
    visits
    |> Enum.reduce([], fn visit, acc ->
      case acc do
        [] ->
          [[visit]]

        [current | rest] ->
          last = List.last(current)

          if NaiveDateTime.diff(visit.inserted_at, last.inserted_at, :second) > @session_gap_sec do
            [[visit] | [current | rest]]
          else
            [current ++ [visit] | rest]
          end
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&build_session_record/1)
  end

  defp build_session_record([first | _] = visits) do
    last = List.last(visits)
    duration_sec = NaiveDateTime.diff(last.inserted_at, first.inserted_at, :second)

    pages =
      visits
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        next = Enum.at(visits, i + 1)

        time_sec =
          if next,
            do: NaiveDateTime.diff(next.inserted_at, v.inserted_at, :second),
            else: nil

        %{
          path: get_in(v.details || %{}, ["path"]) || "/",
          at: v.inserted_at,
          time_sec: time_sec,
          ttfb_ms: get_in(v.details || %{}, ["ttfb_ms"]),
          load_ms: get_in(v.details || %{}, ["load_ms"]),
          recipe_detail_timings: get_in(v.details || %{}, ["recipe_detail_timings"]) || []
        }
      end)

    user_email =
      visits
      |> Enum.find_value(fn v -> get_in(v.details || %{}, ["user_email"]) end)

    user_id =
      visits
      |> Enum.find_value(fn v -> get_in(v.details || %{}, ["user_id"]) end)

    %{
      session_key: first.session_key,
      visitor_id: get_in(first.details || %{}, ["visitor_id"]),
      ip_address: first.ip_address,
      user_id: user_id,
      user_email: user_email,
      started_at: first.inserted_at,
      ended_at: last.inserted_at,
      duration_min: div(duration_sec, 60),
      duration_sec: rem(duration_sec, 60),
      page_count: length(visits),
      pages: pages,
      entry_page: get_in(first.details || %{}, ["path"]) || "/",
      exit_page: get_in(last.details || %{}, ["path"]) || "/",
      referrer: get_in(first.details || %{}, ["referrer"]) || ""
    }
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
