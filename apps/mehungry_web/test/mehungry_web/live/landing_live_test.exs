defmodule MehungryWeb.LandingLiveTest do
  use MehungryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /welcome (nutritionist-led landing)" do
    test "leads with the literature assistant and the complete practice", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/welcome")

      # The signature section — the literature assistant — is present and named.
      assert html =~ "Literature assistant"
      assert html =~ "The evidence, graded."
      assert html =~ "The conclusion, yours."

      # The empower-the-professional spine, not baked condition advice.
      assert html =~ "the judgment stays with you" or
               html =~ "it stays defensibly yours"

      # Completeness + the point-of-care loop.
      assert html =~ "Everything in one place."
      assert html =~ "Your notes find your client."
    end

    test "renders cleanly with an empty research DB (no fabricated 0 counts)", %{conn: conn} do
      # No conditions/analyses seeded: the real research proof numbers are omitted
      # rather than shown as "0".
      {:ok, _lv, html} = live(conn, "/welcome")

      refute html =~ "papers digested"
      refute html =~ "conditions covered"
    end

    test "renders the real evidence-hierarchy ladder from the grading scheme", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/welcome")

      # Rungs come straight from Mehungry.Literature.ResearchType.buckets/0.
      assert html =~ "Systematic reviews &amp; meta-analyses"
      assert html =~ "Randomized &amp; controlled trials"
    end
  end
end
