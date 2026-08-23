defmodule MehungryWeb.ProfessionalLive.GlycemicIndexTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Literature}

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    {:ok, species} = Food.create_foundemental_species(%{name: "Apple"})
    ingredient = ingredient_fixture()
    {:ok, _} = Food.assign_foundemental_ingredient(species.id, ingredient.id, ingredient.name)

    {:ok, study} =
      Literature.upsert_study(%{
        pmid: 55_123,
        title: "GI of apples",
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    Food.record_extracted_gi(study.id, [%{gi_value: 36.0, gi_sem: 2.0, iso_method: true}], [
      species.id
    ])

    [candidate] = Food.list_pending_glycemic_candidates()

    %{conn: conn, species: species, ingredient: ingredient, candidate: candidate}
  end

  test "renders the review queue and the pending value", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/glycemic-index")

    assert html =~ "Glycemic Index"
    assert html =~ "Pending review"
    assert html =~ "Apple"
    assert html =~ "GI 36.0"
    assert html =~ "PMID 55123"
  end

  test "promote writes the GI property onto the species' ingredient", %{
    conn: conn,
    ingredient: ingredient
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/glycemic-index")

    view |> element("form[phx-submit='promote']") |> render_submit()

    assert [property] = Food.list_scientific_properties(ingredient.id)
    assert property.property_key == "glycemic_index"
    assert property.value == 36.0
    assert property.basis == "glucose=100"
  end

  test "reject drops the candidate from the queue", %{conn: conn, candidate: candidate} do
    {:ok, view, _html} = live(conn, ~p"/professional/glycemic-index")

    view
    |> element("button[phx-click='reject'][phx-value-id='#{candidate.id}']")
    |> render_click()

    assert Food.count_pending_glycemic_candidates() == 0
  end

  test "a non-admin is redirected away", %{conn: conn} do
    other = user_fixture(%{email: "not-admin-#{System.unique_integer([:positive])}@example.com"})
    conn = log_in_user(conn, other)

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/glycemic-index")
  end
end
