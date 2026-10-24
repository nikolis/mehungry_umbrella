defmodule Mehungry.Report.Snapshot do
  @moduledoc """
  Gathers the weekly app-status snapshot (`docs/app_status.md`) from all four
  §7 sources in one pass, so the figures can be read and interpreted instead of
  pulled by hand. Driven by `mix report.snapshot`.

  Sources:

    * **DB** (§7.1 / §5) — users, content and engagement counts + the anonymous
      session denominator (`Mehungry.Meta.session_metrics_summary/0`). The
      reporting aggregate reads through `REPORT_RO_DATABASE_URL` (the read-only
      role) when that env var is set, otherwise through the app `Repo`.
    * **GA4** (§7.2) — `Mehungry.Report.GA4.fetch/1`.
    * **Facebook** (§7.3) — `Mehungry.Social.Facebook.page_insights/1`.
    * **Pinterest** (§7.4) — `Mehungry.Social.Pinterest.user_account_analytics/3`.

  Each external source degrades gracefully: when a credential/scope/env is
  missing the section carries a `:skip`/`:error` marker and the rest still
  renders, so you can paste the missing figure by hand.
  """

  alias Mehungry.{Accounts, Meta, Repo}
  alias Mehungry.Accounts.User
  alias Mehungry.Report.{GA4, SearchConsole}
  alias Mehungry.Social.{Facebook, Pinterest}

  @owner_email "nikolisgal@gmail.com"

  @metrics_sql """
  SELECT
    (SELECT count(*) FROM users)                                                AS users_total,
    (SELECT count(*) FROM users WHERE confirmed_at IS NOT NULL)                 AS users_confirmed,
    (SELECT count(*) FROM users WHERE inserted_at > now() - interval '30 days') AS users_new_30d,
    (SELECT count(*) FROM user_profiles WHERE onboarding_level > 0)             AS profiles_onboarded,
    (SELECT count(*) FROM recipes)                                              AS recipes_total,
    (SELECT count(DISTINCT user_id) FROM recipes)                               AS recipe_authors,
    (SELECT count(*) FROM recipes WHERE inserted_at > now() - interval '30 days') AS recipes_new_30d,
    (SELECT count(*) FROM posts)                                                AS posts_total,
    (SELECT count(*) FROM comments)                                             AS comments_total,
    (SELECT count(*) FROM post_upvotes)                                         AS likes_total,
    (SELECT count(*) FROM user_recipes)                                         AS recipe_saves,
    (SELECT count(*) FROM user_follows)                                         AS follows_total,
    (SELECT count(*) FROM meal_plans)                                           AS meal_plans_total,
    (SELECT count(*) FROM beta_signups)                                         AS beta_signups
  """

  @signups_sql """
  SELECT to_char(date_trunc('month', inserted_at),'YYYY-MM') AS month, count(*) AS signups
  FROM users GROUP BY 1 ORDER BY 1
  """

  @metric_keys ~w(users_total users_confirmed users_new_30d profiles_onboarded
                  recipes_total recipe_authors recipes_new_30d posts_total
                  comments_total likes_total recipe_saves follows_total
                  meal_plans_total beta_signups)a

  @doc """
  Collects every section. Options: `:days` (GA4/Pinterest window, default 28).
  """
  def gather(opts \\ []) do
    days = Keyword.get(opts, :days, 28)
    {metrics_rows, signup_rows, owner} = read_prod()

    %{
      captured_at: Date.utc_today(),
      window_days: days,
      db: db_metrics(metrics_rows),
      signups_by_month: Enum.map(signup_rows, fn [m, c] -> {m, c} end),
      sessions: Meta.session_metrics_summary(),
      ga4: GA4.fetch(days),
      search_console: SearchConsole.fetch(days),
      facebook: facebook_insights(owner),
      pinterest: pinterest_analytics(owner, days)
    }
  end

  defp db_metrics([values]) do
    @metric_keys
    |> Enum.zip(values)
    |> Map.new()
  end

  defp facebook_insights(nil), do: {:error, :no_owner_user}
  defp facebook_insights(%User{} = user), do: Facebook.page_insights(user)

  defp pinterest_analytics(nil, _days), do: {:error, :no_owner_user}

  defp pinterest_analytics(%User{} = user, days) do
    today = Date.utc_today()
    Pinterest.user_account_analytics(user, Date.add(today, -days), today)
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc "Human-readable report (what you paste back for interpretation)."
  def to_report(s) do
    """
    App-status snapshot — #{s.captured_at} (window: last #{s.window_days} days)

    ## Users & growth
    #{kv("Registered users", s.db.users_total)}
    #{kv("Email-confirmed", "#{s.db.users_confirmed} (#{pct(s.db.users_confirmed, s.db.users_total)})")}
    #{kv("New users /30d", s.db.users_new_30d)}
    #{kv("Completed onboarding", "#{s.db.profiles_onboarded} (#{pct(s.db.profiles_onboarded, s.db.users_total)})")}

    Signups by month:
    #{signup_lines(s.signups_by_month)}

    ## Content & engagement
    #{kv("Recipes", "#{s.db.recipes_total} (#{s.db.recipe_authors} authors)")}
    #{kv("New recipes /30d", s.db.recipes_new_30d)}
    #{kv("Posts", s.db.posts_total)}
    #{kv("Comments / Likes / Saves / Follows", "#{s.db.comments_total} / #{s.db.likes_total} / #{s.db.recipe_saves} / #{s.db.follows_total}")}
    #{kv("User meal plans", s.db.meal_plans_total)}
    #{kv("Beta signups", s.db.beta_signups)}

    ## Traffic
    #{sessions_block(s.sessions)}
    #{ga4_block(s.ga4)}
    #{gsc_block(s.search_console)}

    ## Social
    Facebook:
    #{facebook_block(s.facebook)}
    Pinterest:
    #{pinterest_block(s.pinterest)}

    ## §6 log row (paste into docs/app_status.md)
    #{to_log_row(s)}
    """
  end

  @doc "A single ready-to-paste §6 snapshot-log table row."
  def to_log_row(s) do
    users = "#{s.db.users_total} (#{s.db.users_confirmed})"
    recipes = "#{s.db.recipes_total} (#{s.db.recipe_authors})"

    engagement =
      "#{s.db.comments_total} / #{s.db.likes_total} / #{s.db.recipe_saves} / #{s.db.follows_total}"

    traffic = traffic_summary(s)
    "| #{s.captured_at} | #{users} | #{s.db.users_new_30d} | #{recipes} | #{engagement} | #{traffic} | |"
  end

  defp traffic_summary(s) do
    anon =
      case s.sessions do
        %{sessions_total: n} when n > 0 -> "#{n} anon sessions all-time"
        _ -> "no anon sessions yet"
      end

    ga4 =
      case s.ga4 do
        {:ok,
         %{
           totals: %{sessions: raw, engaged_sessions: raw_engaged},
           bot_totals: %{sessions: dc, engaged_sessions: dc_engaged}
         }}
        when is_integer(dc) ->
          real = max(raw_engaged - dc_engaged, 0)
          "~#{real} GA4 real sessions/#{s.window_days}d (#{raw} raw incl. bots)"

        {:ok, %{totals: %{sessions: n}}} ->
          "~#{n} GA4 sessions/#{s.window_days}d"

        {:skip, _} ->
          "GA4 n/a"

        _ ->
          "GA4 error"
      end

    gsc =
      case s.search_console do
        {:ok, %{totals: %{impressions: imp}, foods: foods}} ->
          "#{imp} GSC impr (/foods: #{foods[:impressions] || 0})"

        {:skip, _} ->
          "GSC n/a"

        _ ->
          "GSC error"
      end

    "#{ga4}; #{gsc}; #{anon}"
  end

  # ---------------------------------------------------------------------------
  # Block formatters
  # ---------------------------------------------------------------------------

  defp sessions_block(%{sessions_total: 0}), do: "  (no anonymous sessions recorded yet)"

  defp sessions_block(%{sessions_total: n, first_day: first, last_day: last, avg_seconds: avg}) do
    "  Anonymous sessions (consent-independent): #{n} total, #{first} → #{last}, avg #{avg}s/session"
  end

  defp ga4_block({:ok, g}) do
    t = g.totals
    b = Map.get(g, :bot_totals, %{})
    cities = Map.get(g, :cities, [])

    raw = t[:sessions] || 0
    raw_engaged = t[:engaged_sessions] || 0
    non_engaged = raw - raw_engaged

    dc = b[:sessions]
    dc_engaged = b[:engaged_sessions] || 0
    # Best "real human" proxy: engaged (>10s / multi-view) AND not from a
    # datacenter city. Subtract datacenter *engaged* sessions so the two
    # filters don't double-count.
    real = if is_integer(dc), do: max(raw_engaged - dc_engaged, 0), else: nil

    split =
      if is_integer(dc) do
        "    datacenter-city sessions (infra/bot — see cities): #{dc}\n" <>
          "    non-engaged sessions (<10s / single-view — bot-like): #{non_engaged}\n" <>
          "    REAL audience (engaged >10s, non-datacenter): #{real} sessions"
      else
        "    bot split: unavailable (datacenter totals: #{inspect(b[:error])})"
      end

    """
      GA4 (last #{g.window_days}d) — ALL traffic incl. bots: #{raw} sessions, #{t[:active_users]} active users, #{t[:new_users]} new users
    #{split}
        engagement rate #{t[:engagement_rate]}, avg session #{t[:avg_session_seconds]}s (all traffic)
        channels: #{dim_line(g.channels)}
        countries: #{dim_line(g.countries)}
        cities (curate datacenter denylist from here): #{dim_line(cities)}
        top pages: #{dim_line(g.pages)}\
    """
  end

  defp ga4_block({:skip, reason}), do: "  GA4: not configured (#{reason}) — paste by hand (see §5.3)"
  defp ga4_block({:error, reason}), do: "  GA4: error — #{inspect(reason)}"

  defp gsc_block({:ok, g}) do
    t = g.totals
    f = g.foods

    """
      Search Console (last #{g.window_days}d): #{t[:clicks]} clicks, #{t[:impressions]} impressions, CTR #{t[:ctr]}%, avg pos #{t[:position]}
        /foods pages: #{f[:clicks]} clicks, #{f[:impressions]} impressions (the organic leading indicator)
        top queries: #{gsc_line(g.top_queries)}
        top pages: #{gsc_line(g.top_pages)}\
    """
  end

  defp gsc_block({:skip, reason}),
    do: "  Search Console: not configured (#{reason}) — see §5.3 / §7.2"

  defp gsc_block({:error, reason}), do: "  Search Console: error — #{inspect(reason)}"

  defp dim_line([]), do: "(none)"

  defp dim_line(rows) do
    rows
    |> Enum.map(fn %{label: l, value: v} -> "#{l}=#{v}" end)
    |> Enum.join(", ")
  end

  defp gsc_line([]), do: "(none)"

  defp gsc_line(rows) do
    Enum.map_join(rows, ", ", fn r -> "#{r[:label]}=#{r[:impressions]}impr" end)
  end

  defp facebook_block({:ok, pages}) do
    Enum.map_join(pages, "\n", fn p ->
      core =
        "followers=#{fb_val(p[:followers])}, reach/28d=#{fb_val(p[:reach_28d])}, impressions/28d=#{fb_val(p[:impressions_28d])}, engagements/28d=#{fb_val(p[:engagements_28d])}"

      "  • #{p[:name]}: #{core}#{fb_insights_note(p[:insights_note])}"
    end)
  end

  defp facebook_block({:error, :not_connected}), do: "  (no Facebook Page connected)"
  defp facebook_block({:error, :no_owner_user}), do: "  (owner user not found)"
  defp facebook_block({:error, reason}), do: "  error — #{inspect(reason)}"

  defp fb_val(nil), do: "n/a"
  defp fb_val(v), do: v

  # Only present when every insight metric came back empty (e.g. token lacks
  # read_insights, or all names are deprecated) — follower counts still show.
  defp fb_insights_note(nil), do: ""

  defp fb_insights_note(note),
    do: "  [insights n/a — #{String.slice(to_string(note), 0, 140)}]"

  defp pinterest_block({:ok, m}) do
    "  impressions=#{m.impressions}, saves=#{m.saves}, pin clicks=#{m.pin_clicks}, outbound clicks=#{m.outbound_clicks}, engagements=#{m.engagements}"
  end

  defp pinterest_block({:error, :sandbox}),
    do: "  (PINTEREST_ENV is not 'live' — sandbox returns no real analytics; set PINTEREST_ENV=live)"

  defp pinterest_block({:error, :not_connected}), do: "  (no Pinterest account connected)"
  defp pinterest_block({:error, :no_owner_user}), do: "  (owner user not found)"

  defp pinterest_block({:error, {:token_refresh_failed, reason}}) do
    "  token expired and refresh failed — #{pinterest_refresh_hint(reason)}"
  end

  defp pinterest_block({:error, reason}), do: "  error — #{inspect(reason)}"

  defp pinterest_refresh_hint(:no_refresh_token),
    do: "no refresh token stored → reconnect Pinterest in the app"

  defp pinterest_refresh_hint({:http_error, status, body}),
    do:
      "Pinterest rejected the refresh (HTTP #{status}: #{String.slice(to_string(body), 0, 160)}) → check PINTEREST_CLIENT_ID/SECRET match the app that minted the token, else reconnect"

  defp pinterest_refresh_hint(reason), do: inspect(reason)

  defp signup_lines([]), do: "  (none)"

  defp signup_lines(rows) do
    Enum.map_join(rows, "\n", fn {month, count} -> "  #{month}: #{count}" end)
  end

  defp kv(label, value), do: "  #{label}: #{value}"

  defp pct(_part, 0), do: "0%"
  defp pct(part, total), do: "#{round(part * 100 / total)}%"

  # ---------------------------------------------------------------------------
  # DB access — read-only role when configured, else the app Repo
  # ---------------------------------------------------------------------------

  # Returns `{metrics_rows, signup_rows, owner}`. When `REPORT_RO_DATABASE_URL`
  # is set, every read — the aggregates AND the owner's social tokens — goes
  # through one transient read-only prod connection, so the task can run from a
  # local checkout (app Repo = dev) while reading prod safely. Unset, it uses the
  # app Repo + `Accounts` (the DATABASE_URL=prod operating mode).
  defp read_prod do
    case System.get_env("REPORT_RO_DATABASE_URL") do
      url when is_binary(url) and url != "" ->
        {:ok, conn} = start_ro(url)

        try do
          {Postgrex.query!(conn, @metrics_sql, []).rows,
           Postgrex.query!(conn, @signups_sql, []).rows, ro_owner(conn)}
        after
          GenServer.stop(conn)
        end

      _ ->
        {Repo.query!(@metrics_sql, []).rows, Repo.query!(@signups_sql, []).rows,
         Accounts.get_user_by_email(@owner_email)}
    end
  end

  # Build a minimal %User{} carrying just the social tokens, read through the RO
  # connection. jsonb is cast to text and decoded here so this works regardless
  # of the transient connection's Postgrex JSON config.
  defp ro_owner(conn) do
    sql =
      "SELECT id, email, facebook_token::text, pinterest_token::text FROM users WHERE email = $1"

    case Postgrex.query!(conn, sql, [@owner_email]).rows do
      [[id, email, fb, pin]] ->
        %User{
          id: id,
          email: email,
          facebook_token: decode_json(fb),
          pinterest_token: decode_json(pin)
        }

      _ ->
        nil
    end
  end

  defp decode_json(nil), do: %{}

  defp decode_json(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  @ro_url_hint "Expected a URL like postgres://report_ro.<project-ref>:<password>@<host>:6543/postgres?sslmode=require"

  # Parse REPORT_RO_DATABASE_URL with Ecto's own (encoding-aware) parser and open
  # a 1-connection Postgrex pool. Raises a clear, credential-free error when the
  # URL is unparseable or has no host (Postgrex would otherwise fail deep inside
  # `endpoints/1` with the details hidden "as they may contain credentials").
  defp start_ro(url) do
    parsed =
      try do
        Ecto.Repo.Supervisor.parse_url(url)
      rescue
        e ->
          reraise ArgumentError,
                  "REPORT_RO_DATABASE_URL is not a valid postgres URL (#{Exception.message(e)}). #{@ro_url_hint}",
                  __STACKTRACE__
      end

    host = Keyword.get(parsed, :hostname)

    unless is_binary(host) and host != "" do
      raise ArgumentError,
            "REPORT_RO_DATABASE_URL has no host (got #{inspect(host)}). #{@ro_url_hint}"
    end

    opts =
      parsed
      |> Keyword.take([:hostname, :port, :username, :password, :database])
      |> Keyword.merge(pool_size: 1, connect_timeout: 10_000)
      |> Keyword.merge(socket_opts(host))
      |> maybe_ssl(host, Keyword.get(parsed, :sslmode))

    Postgrex.start_link(opts)
  end

  # Supabase *direct* hosts (db.<ref>.supabase.co) are IPv6-only — no A record —
  # so Postgrex's default IPv4 lookup nxdomains. Detect a host with no IPv4 and
  # switch the socket to IPv6. The pooler host has an A record, so it's unaffected.
  defp socket_opts(host) do
    case :inet.getaddr(to_charlist(host), :inet) do
      {:ok, _ipv4} -> []
      {:error, _} -> [socket_options: [:inet6]]
    end
  end

  # Supabase (and most managed Postgres) require TLS. Enable it when the URL asks
  # for it (sslmode) or the host is clearly remote; verification is off (the
  # report is a trusted-operator read, not a browser trust context).
  defp maybe_ssl(opts, host, sslmode) do
    remote? = host not in ["localhost", "127.0.0.1"]

    if sslmode in ["require", "verify-ca", "verify-full"] or (sslmode in [nil, ""] and remote?) do
      Keyword.put(opts, :ssl, verify: :verify_none, server_name_indication: to_charlist(host))
    else
      opts
    end
  end
end
