defmodule MehungryWeb.NutritionistLive.ArticleTest do
  @moduledoc """
  Smoke tests for professional article authoring + public rendering: a
  nutritionist creates an article, adds a paragraph and a disease reference,
  publishes it, and the published body is served (dead render) at the public URL
  while a draft's URL redirects.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.{Professionals, Repo, Subscriptions}
  alias Mehungry.Health.Condition

  setup %{conn: conn} do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

    {:ok, profile} =
      Professionals.create_professional_profile(%{
        user_id: nutritionist.id,
        specialization: "Dietitian",
        display_name: "Maria Papadaki",
        city: "Rethymno",
        bio: "Clinical dietitian.",
        is_public: true
      })

    %{conn: log_in_user(conn, nutritionist), profile: profile}
  end

  test "author creates, fills, references and publishes an article; public page renders it",
       %{conn: conn, profile: profile} do
    condition = Repo.insert!(%Condition{name: "Kidney Stones"})

    {:ok, article} =
      Professionals.create_article(%{
        "professional_profile_id" => profile.id,
        "title" => "Untitled article"
      })

    {:ok, view, _html} = live(conn, "/nutritionist/articles/#{article.id}/edit")

    # Save the header.
    view
    |> form("form[phx-submit='save_article']",
      article: %{title: "Oxalates 101", summary: "A short guide."}
    )
    |> render_submit()

    # Add a paragraph and fill its body.
    render_click(view, "add_paragraph")

    view
    |> form("form[phx-submit='save_paragraph']", %{body: "Spinach is high in oxalates."})
    |> render_submit()

    # Cite a disease from that paragraph.
    view
    |> form("form[phx-submit='add_condition_ref']", %{condition_id: condition.id})
    |> render_submit()

    # Publish.
    render_click(view, "publish")

    # Draft edits re-slug from the title, so the placeholder slug is gone.
    published = Professionals.get_published_article_by_slug("oxalates-101")
    assert published
    assert [paragraph] = published.paragraphs
    assert paragraph.body == "Spinach is high in oxalates."
    assert [ref] = paragraph.references
    assert ref.reference_type == "condition"
    assert ref.condition_id == condition.id

    # Public dead render (logged out) carries the body + Article JSON-LD.
    public_conn = get(build_conn(), "/nutritionists/#{profile.slug}/articles/oxalates-101")
    body = html_response(public_conn, 200)
    assert body =~ "Spinach is high in oxalates."
    assert body =~ "Kidney Stones"
    assert body =~ "\"@type\":\"Article\""
  end

  test "a draft article's public URL redirects to the profile", %{conn: conn, profile: profile} do
    {:ok, _draft} =
      Professionals.create_article(%{
        "professional_profile_id" => profile.id,
        "title" => "Secret Draft"
      })

    # Logged out: the draft slug is not published, so it redirects to the profile.
    assert {:error, {:live_redirect, %{to: to}}} =
             live(build_conn(), "/nutritionists/#{profile.slug}/articles/secret-draft")

    assert to == "/nutritionists/#{profile.slug}"
    # (conn param retained so the parent `conn` setup stays used)
    assert conn
  end
end
