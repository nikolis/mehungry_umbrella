defmodule MehungryWeb.ProfessionalLive.TranslationsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Languages.{Coverage, TranslationRegistry, Translations}

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    conn = log_in_user(conn, user_fixture(%{email: @admin_email}))
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{conn: conn, compound: oxalate}
  end

  test "hub lists resources with coverage", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/translations")

    assert html =~ "Translation Coverage"
    assert html =~ "Compounds"
    assert html =~ "Ingredients"
  end

  test "panel lists missing items and links to the editor", %{conn: conn, compound: compound} do
    {:ok, view, _html} = live(conn, ~p"/professional/translations/compounds")

    assert has_element?(view, "a[href='/professional/translations/compounds/#{compound.id}']")
    assert render(view) =~ "Oxalate"
  end

  test "verifying a draft moves it out of the missing bucket", %{conn: conn, compound: compound} do
    descriptor = TranslationRegistry.get("compounds")

    {:ok, _} =
      Translations.upsert(descriptor, compound.id, "el", %{name: "Οξαλικό"}, status: "ai_draft")

    assert Coverage.coverage(descriptor, "el").ai_draft == 1

    {:ok, view, _html} = live(conn, ~p"/professional/translations/compounds?filter=ai_draft")

    view
    |> element("button[phx-click=verify][phx-value-id='#{compound.id}']")
    |> render_click()

    assert Coverage.coverage(descriptor, "el").verified == 1
    assert Coverage.coverage(descriptor, "el").ai_draft == 0
  end
end
