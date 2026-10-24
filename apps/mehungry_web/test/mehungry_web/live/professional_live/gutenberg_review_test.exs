defmodule MehungryWeb.ProfessionalLive.GutenbergReviewTest do
  @moduledoc """
  Covers the admin Gutenberg review LiveView: the book picker, loading a parsed
  recipe into the form beside the verbatim book excerpt, skipping (records +
  advances), resuming past already-reviewed recipes, and the "all done" state.
  The Gutenberg download is stubbed via `:gutenberg_client`.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.FoodData.Gutenberg.Imports

  @admin_email Application.compile_env(:mehungry, :admin_email)

  # ebook 6385 (Simple Italian Cookery) is catalogued as a :heading book.
  @book_id "6385"

  @book_text """
  *** START OF THE PROJECT GUTENBERG EBOOK SIMPLE ITALIAN COOKERY ***

  BEEF SOUP STOCK
  (_Brodo di Carne_)

    1 cup olive oil
    1 onion

  Boil the beef and vegetables. Skim occasionally.


  CHICKEN BROTH
  (_Brodo di Capone_)

  This is made like the meat stock, substituting a fowl.

  *** END OF THE PROJECT GUTENBERG EBOOK SIMPLE ITALIAN COOKERY ***
  """

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    Application.put_env(:mehungry, :gutenberg_client_books, %{
      @book_id => {:ok, String.replace(@book_text, "\n", "\r\n")}
    })

    # The resolver needs a gram unit + an ingredient (with a "cup" portion) that
    # a book line can match, so the saved recipe has ≥1 ingredient (required).
    measurement_unit_fixture(%{name: "grams"})
    olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})

    %Mehungry.Food.IngredientPortion{}
    |> Ecto.Changeset.change(%{
      ingredient_id: olive.id,
      measurement_unit_id: nil,
      amount: 1.0,
      gram_weight: 218.0,
      description: "cup"
    })
    |> Mehungry.Repo.insert!()

    on_exit(fn -> Application.delete_env(:mehungry, :gutenberg_client_books) end)

    %{conn: conn}
  end

  test "the picker lists catalogued books", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/gutenberg-review")

    assert html =~ "Gutenberg import review"
    assert html =~ "Simple Italian Cookery"
    assert html =~ "Browse recipes"
  end

  test "opening a book shows the searchable recipe list (not a blind next)", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}")

    assert html =~ "Simple Italian Cookery"
    # Both parsed recipes are listed as choices (titles are the verbatim headings).
    assert html =~ "BEEF SOUP STOCK"
    assert html =~ "CHICKEN BROTH"
    # The search box is the primary way to pick a recipe.
    assert html =~ ~s(name="q")
  end

  test "fuzzy search filters the recipe list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}")

    html = view |> form("form[phx-change=search]", %{q: "chicken"}) |> render_change()

    assert html =~ "CHICKEN BROTH"
    refute html =~ "BEEF SOUP STOCK"
  end

  test "a specific recipe can be opened by index into the review form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}/2")
    # The editable form holds the opened recipe (title is titleized on import).
    assert html =~ "Chicken Broth"
    assert html =~ "of 2"
  end

  test "skip records the recipe ref and returns to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}/1")

    html = view |> element("button", "Skip") |> render_click()

    assert Imports.status_for(Imports.ref(@book_id, 1)) == "skipped"
    # Back on the recipe list, where the skipped recipe is badged.
    assert html =~ "BEEF SOUP STOCK"
    assert html =~ "skipped"
  end

  test "the recipe list badges already-reviewed recipes", %{conn: conn} do
    Imports.mark_completed(Imports.ref(@book_id, 1), nil)

    {:ok, _view, html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}")

    assert html =~ "BEEF SOUP STOCK"
    assert html =~ "completed"
  end

  test "a failed book download shows a distinct retry state, not 'all caught up'", %{conn: conn} do
    Application.put_env(:mehungry, :gutenberg_client_books, %{@book_id => {:error, :timeout}})

    {:ok, _view, html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}")

    assert html =~ "load the book"
    assert html =~ "Retry"
    refute html =~ "All caught up"
  end

  test "saving stages the recipe private and tagged source=gutenberg", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}/1")

    # Submit the pre-filled review form (defaults to "Saving as private").
    view |> form("#create-recipe-form") |> render_submit()

    assert [recipe] = saved_gutenberg_recipes()
    # Provenance + visibility survive the form save (the form doesn't render them).
    assert recipe.source == "gutenberg"
    assert recipe.private == true
    assert recipe.original_url == "https://www.gutenberg.org/ebooks/6385"
    # Recorded as completed so review resumes past it.
    assert Imports.status_for(Imports.ref(@book_id, 1)) == "completed"
  end

  test "ticking Publish saves the recipe public", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/gutenberg-review/#{@book_id}/1")

    view |> element("button", "Saving as private") |> render_click()
    view |> form("#create-recipe-form") |> render_submit()

    assert [recipe] = saved_gutenberg_recipes()
    assert recipe.private == false
    assert recipe.source == "gutenberg"
  end

  defp saved_gutenberg_recipes do
    import Ecto.Query
    Mehungry.Repo.all(from r in Mehungry.Food.Recipe, where: r.source == "gutenberg")
  end

  test "non-admins are redirected", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/gutenberg-review")
  end
end
