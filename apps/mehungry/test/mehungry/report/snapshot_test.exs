defmodule Mehungry.Report.SnapshotTest do
  use ExUnit.Case, async: true

  alias Mehungry.Report.Snapshot

  defp sample(overrides \\ %{}) do
    base = %{
      captured_at: ~D[2026-10-24],
      window_days: 28,
      db: %{
        users_total: 50,
        users_confirmed: 16,
        users_new_30d: 4,
        profiles_onboarded: 15,
        recipes_total: 85,
        recipe_authors: 5,
        recipes_new_30d: 4,
        posts_total: 483,
        comments_total: 1,
        likes_total: 0,
        recipe_saves: 25,
        follows_total: 8,
        meal_plans_total: 0,
        beta_signups: 0
      },
      signups_by_month: [{"2026-09", 2}, {"2026-10", 2}],
      sessions: %{sessions_total: 200, first_day: ~D[2026-10-10], last_day: ~D[2026-10-24], avg_seconds: 480},
      ga4: {:skip, "GA4_SA_KEY not set"},
      search_console: {:skip, "GSC_SITE_URL not set"},
      facebook: {:error, :not_connected},
      pinterest: {:error, :sandbox}
    }

    Map.merge(base, overrides)
  end

  describe "to_log_row/1" do
    test "emits a §6-shaped markdown row with confirmed/authors folded in" do
      row = Snapshot.to_log_row(sample())

      assert row ==
               "| 2026-10-24 | 50 (16) | 4 | 85 (5) | 1 / 0 / 25 / 8 | GA4 n/a; GSC n/a; 200 anon sessions all-time | |"
    end

    test "uses GA4 session count in the traffic column when GA4 resolved" do
      ga4 = {:ok, %{window_days: 28, totals: %{sessions: 142}, channels: [], countries: [], pages: []}}
      row = Snapshot.to_log_row(sample(%{ga4: ga4}))

      assert row =~ "~142 GA4 sessions/28d"
    end

    test "folds Search Console impressions (incl. /foods) into the traffic column" do
      gsc =
        {:ok,
         %{window_days: 28, totals: %{impressions: 900}, foods: %{impressions: 120},
           top_queries: [], top_pages: []}}

      row = Snapshot.to_log_row(sample(%{search_console: gsc}))

      assert row =~ "900 GSC impr (/foods: 120)"
    end

    test "reports absence of anonymous sessions" do
      sessions = %{sessions_total: 0, first_day: nil, last_day: nil, avg_seconds: 0}
      row = Snapshot.to_log_row(sample(%{sessions: sessions}))

      assert row =~ "no anon sessions yet"
    end
  end

  describe "to_report/1" do
    test "renders each section and degradation notes" do
      report = Snapshot.to_report(sample())

      assert report =~ "Registered users: 50"
      assert report =~ "Email-confirmed: 16 (32%)"
      assert report =~ "Recipes: 85 (5 authors)"
      assert report =~ "GA4: not configured (GA4_SA_KEY not set)"
      assert report =~ "Search Console: not configured (GSC_SITE_URL not set)"
      assert report =~ "no Facebook Page connected"
      assert report =~ "PINTEREST_ENV is not 'live'"
    end

    test "renders resolved GA4 + social metrics when present" do
      overrides = %{
        ga4:
          {:ok,
           %{
             window_days: 28,
             totals: %{sessions: 142, active_users: 110, new_users: 40, engagement_rate: 0.58, avg_session_seconds: 95},
             channels: [%{label: "Direct", value: 90}, %{label: "Organic Search", value: 12}],
             countries: [%{label: "Greece", value: 130}],
             pages: [%{label: "/home", value: 200}]
           }},
        search_console:
          {:ok,
           %{
             window_days: 28,
             totals: %{clicks: 4, impressions: 900, ctr: 0.44, position: 28.7},
             foods: %{clicks: 1, impressions: 120},
             top_queries: [%{label: "greek recipes", impressions: 300}],
             top_pages: [%{label: "/foods/spinach", impressions: 80}]
           }},
        facebook: {:ok, [%{name: "Mehungry", id: "1", followers: 12, fans: 12, reach_28d: 90, impressions_28d: 117, engagements_28d: 0}]},
        pinterest: {:ok, %{impressions: 73, saves: 0, pin_clicks: 5, outbound_clicks: 3, engagements: 12}}
      }

      report = Snapshot.to_report(sample(overrides))

      assert report =~ "142 sessions, 110 active users, 40 new users"
      assert report =~ "Direct=90, Organic Search=12"
      assert report =~ "Search Console (last 28d): 4 clicks, 900 impressions"
      assert report =~ "/foods pages: 1 clicks, 120 impressions"
      assert report =~ "Mehungry: followers=12"
      assert report =~ "outbound clicks=3"
    end

    test "shows follower counts but flags insights when no metric resolved" do
      fb =
        {:ok,
         [%{name: "Mehungry", id: "1", followers: 12, fans: 12, insights_note: "HTTP 400: (#100) invalid metric"}]}

      report = Snapshot.to_report(sample(%{facebook: fb}))

      assert report =~ "Mehungry: followers=12"
      assert report =~ "reach/28d=n/a"
      assert report =~ "[insights n/a — HTTP 400: (#100) invalid metric]"
    end
  end
end
