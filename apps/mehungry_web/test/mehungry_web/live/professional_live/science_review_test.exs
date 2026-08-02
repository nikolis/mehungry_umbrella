defmodule MehungryWeb.ProfessionalLive.ScienceReviewTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Literature}

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    conn = log_in_user(conn, user_fixture(%{email: @admin_email}))

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, study} =
      Literature.upsert_study(%{
        pmid: 11_111,
        title: "Oxalate content of Spinacia oleracea",
        journal: "J Food Sci",
        publication_date: "2019",
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: spinach.id,
        search_term: "Spinacia oleracea Oxalate",
        scientific_name: "Spinacia oleracea"
      })

    {:ok, _} =
      Literature.upsert_entity_mention(%{
        study_id: study.id,
        entity_type: "chemical",
        text_span: "oxalate",
        normalized_identifier: "mesh:D010070",
        offset: 0,
        compound_id: oxalate.id
      })

    %{conn: conn, study: study, spinach: spinach, oxalate: oxalate}
  end

  describe "Studies review page" do
    test "lists studies with counts and expands to ingredients + mentions", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/professional/science/studies")

      assert html =~ "Discovered Studies"
      assert html =~ "Oxalate content of Spinacia oleracea"
      assert html =~ "1</span> ingredients"
      assert html =~ "1</span> mentions"

      html = view |> element("button", "Details") |> render_click()
      assert html =~ "spinach"
      assert html =~ "oxalate"
    end

    test "search filters by title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/professional/science/studies")

      html = view |> form("form", %{q: "nonsense-xyz"}) |> render_submit()
      refute html =~ "Oxalate content of Spinacia oleracea"
      assert html =~ "0 results"
    end

    test "non-admin is redirected" do
      conn = log_in_user(build_conn(), user_fixture(%{email: "no@example.com"}))
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/science/studies")
    end
  end

  describe "Entities review page" do
    test "summarizes mentions and expands to the resolved compound", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/professional/science/entities")

      assert html =~ "Extracted Entities"
      assert html =~ "Oxalate content of Spinacia oleracea"
      assert html =~ "1</span> chem"

      html = view |> element("button", "Mentions") |> render_click()
      # chemical mention shows the compound it resolved to
      assert html =~ "Oxalate"
    end

    test "non-admin is redirected" do
      conn = log_in_user(build_conn(), user_fixture(%{email: "no@example.com"}))
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/science/entities")
    end
  end
end
