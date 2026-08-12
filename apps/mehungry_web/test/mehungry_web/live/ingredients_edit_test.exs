defmodule MehungryWeb.IngredientsEditTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.Taxonomies

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Bio Nutritional", slug: "bio-nutritional"})

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})

    {:ok, beef} =
      Taxonomies.create_node(%{
        name: "Beef",
        slug: "beef",
        taxonomy_id: taxonomy.id,
        parent_id: meat.id
      })

    ingredient = ingredient_fixture(%{name: "brisket"})

    %{conn: conn, taxonomy: taxonomy, beef: beef, ingredient: ingredient}
  end

  test "renders the taxonomy select with a leaf option", %{conn: conn, ingredient: ingredient} do
    {:ok, _view, html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")

    assert html =~ "Taxonomy (Bio Nutritional)"
    assert html =~ ~s(name="ingredient[taxonomy_node_id]")
    assert html =~ "Meat &gt; Beef"
  end

  test "saving with a chosen node persists a reviewed manual mapping", ctx do
    %{conn: conn, ingredient: ingredient, beef: beef, taxonomy: taxonomy} = ctx
    {:ok, view, _html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")

    view
    |> form("#ingredient-details-form", %{
      "ingredient" => %{
        "name" => ingredient.name,
        "category_id" => to_string(ingredient.category_id),
        "taxonomy_node_id" => to_string(beef.id)
      }
    })
    |> render_submit()

    assert Food.get_ingredient_node_id(taxonomy.id, ingredient.id) == beef.id
  end

  describe "editing nested portions/nutrients/translations" do
    test "removing a portion drops its row and deletes it on save", ctx do
      %{conn: conn, ingredient: ingredient} = ctx
      unit = measurement_unit_fixture(%{name: "gram"})
      {:ok, _p0} = add_portion(ingredient, unit, 100.0)
      {:ok, p1} = add_portion(ingredient, unit, 250.0)

      {:ok, view, html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")
      # Both portions are rendered up front.
      assert html =~ "value=\"100.0\""
      assert html =~ "value=\"250.0\""

      # Clicking the ✕ on the second portion (index 1) only stages the removal —
      # the row disappears but nothing is persisted yet.
      removed_html = submit_action(view, ingredient, "remove_portion:1")
      refute removed_html =~ "value=\"250.0\""
      refute removed_html =~ "Updated successfully"
      assert portion_count(ingredient) == 2

      # A plain save persists the deletion (on_replace: :delete removes the row).
      save(view, ingredient)
      assert portion_count(ingredient) == 1
      refute Enum.any?(portions(ingredient), &(&1.id == p1.id))
    end

    test "removing a nutrient stages a deletion instead of silently saving", ctx do
      %{conn: conn, ingredient: ingredient} = ctx
      mg = measurement_unit_fixture(%{name: "milligram"})
      {:ok, nutrient} = Food.create_nutrient(%{name: "Iron", rank: 1, measurement_unit_id: mg.id})
      {:ok, _in} = Food.create_ingredient_nutrient(%{ingredient_id: ingredient.id, nutrient_id: nutrient.id, amount: 5.5})

      {:ok, view, html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")
      assert html =~ "value=\"5.5\""

      # Before the fix this hit the fall-through save clause and flashed
      # "Updated successfully" while keeping the nutrient. Now it just drops the row.
      removed_html = submit_action(view, ingredient, "remove_nutrient:0")
      refute removed_html =~ "value=\"5.5\""
      refute removed_html =~ "Updated successfully"
      assert nutrient_count(ingredient) == 1

      save(view, ingredient)
      assert nutrient_count(ingredient) == 0
    end

    test "adding a translation renders a new empty row without saving", ctx do
      %{conn: conn, ingredient: ingredient} = ctx
      {:ok, view, html} = live(conn, ~p"/professional/ingredients/#{ingredient.id}/edit")
      assert translation_rows(html) == 1

      # Before the fix "add_ingredient_translation" fell through to the save clause.
      added_html = submit_action(view, ingredient, "add_ingredient_translation")
      assert translation_rows(added_html) == 2
      refute added_html =~ "Updated successfully"
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp add_portion(ingredient, unit, grams) do
    Food.create_ingredient_portion(%{
      ingredient_id: ingredient.id,
      measurement_unit_id: unit.id,
      gram_weight: grams
    })
  end

  defp portions(ingredient), do: Food.get_ingredient_details!(ingredient.id).ingredient_portions
  defp portion_count(ingredient), do: length(portions(ingredient))

  defp nutrient_count(ingredient),
    do: length(Food.get_ingredient_details!(ingredient.id).ingredient_nutrients)

  defp translation_rows(html) do
    html
    |> String.split("remove_ingredient_translation:")
    |> length()
    |> Kernel.-(1)
  end

  # Emulate clicking one of the add/remove submit buttons: the form's DOM values
  # (portion rows, *_sort hidden inputs, name, category) serialize automatically,
  # and the pressed button's `_action` is injected as an extra param.
  defp submit_action(view, ingredient, action) do
    view
    |> form("#ingredient-details-form", %{"ingredient" => base_params(ingredient)})
    |> render_submit(%{"ingredient" => %{"_action" => action}})
  end

  defp save(view, ingredient) do
    view
    |> form("#ingredient-details-form", %{"ingredient" => base_params(ingredient)})
    |> render_submit()
  end

  defp base_params(ingredient) do
    %{"name" => ingredient.name, "category_id" => to_string(ingredient.category_id)}
  end
end
