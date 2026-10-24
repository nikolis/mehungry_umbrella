defmodule MehungryWeb.RecipeNutrientsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MehungryWeb.RecipeComponents

  defp nutrients do
    %{
      "protein" => %{
        "name" => "Protein",
        "amount" => 10,
        "measurement_unit" => "g",
        "children" => [
          %{"name" => "Protein", "amount" => 10, "measurement_unit" => "g", "children" => []}
        ]
      }
    }
  end

  describe "recipe_nutrients/2 (plain-map form, used by the calendar summary)" do
    test "honors the locale argument when the map carries no :locale" do
      # The calendar passes locale positionally with a bare `%{nutrients:, id:}`
      # map — it must still localize (regression: the arg was ignored).
      html =
        %{id: "overview_day-2026-10-18", nutrients: nutrients()}
        |> RecipeComponents.recipe_nutrients("el")
        |> rendered_to_string()

      assert html =~ "Πρωτεΐνη"
      refute html =~ ">Protein<"
    end

    test "scopes the accordion DOM ids to the card id so stacked cards don't collide" do
      html_a =
        %{id: "overview_day-2026-10-18", nutrients: nutrients()}
        |> RecipeComponents.recipe_nutrients("en")
        |> rendered_to_string()

      html_b =
        %{id: "overview_week-2026-10-12", nutrients: nutrients()}
        |> RecipeComponents.recipe_nutrients("en")
        |> rendered_to_string()

      # The checkbox-hack ids must be distinct between the two cards, otherwise a
      # <label for=...> toggles the first card's rows for every card.
      assert html_a =~ ~s(id="nutrition-overview_day-2026-10-18-l1-i0")
      assert html_b =~ ~s(id="nutrition-overview_week-2026-10-12-l1-i0")
      refute html_a =~ "nutrition-overview_week"
    end
  end
end
