defmodule MehungryWeb.MealPlanShareTextTest do
  @moduledoc """
  The copy-ready social captions for a published plan must stay truthful (same
  macro numbers the page shows), carry the plan link + hashtags, skip empty days,
  and localize weekday labels.
  """
  use ExUnit.Case, async: true

  alias MehungryWeb.MealPlanShareText

  @url "https://www.m3hungry.com/meal-plans/my-week"

  # A minimal published-plan snapshot (string-keyed days/macros, like the DB
  # column shapes). Monday + Wednesday have meals; the rest are empty.
  defp plan(overrides \\ %{}) do
    base = %{
      title: "Anti-inflammatory week · Oct 5",
      goal_label: "Anti-inflammatory",
      locale: "en",
      recipe_count: 3,
      og_image_url: "https://cdn.example.com/card.png",
      macros: %{
        "energy_kcal" => 1850,
        "protein_g" => 95.0,
        "carbs_g" => 180.4,
        "fat_g" => 60.0
      },
      days: [
        %{
          "index" => 0,
          "date" => "2026-10-05",
          "label" => "Monday",
          "meals" => [
            %{
              "meal_type" => "lunch",
              "items" => [%{"kind" => "recipe", "title" => "Lentil Soup"}]
            },
            %{
              "meal_type" => "dinner",
              "items" => [%{"kind" => "recipe", "title" => "Grilled Salmon"}]
            }
          ]
        },
        %{"index" => 1, "date" => "2026-10-06", "label" => "Tuesday", "meals" => []},
        %{
          "index" => 2,
          "date" => "2026-10-07",
          "label" => "Wednesday",
          "meals" => [
            %{
              "meal_type" => "breakfast",
              "items" => [%{"kind" => "ingredient", "ingredient_id" => 7, "title" => "Spinach"}]
            }
          ]
        }
      ]
    }

    Map.merge(base, overrides)
  end

  defp opts(extra \\ []),
    do: Keyword.merge([share_url: @url, locale: "en"], extra)

  describe "image_caption/2" do
    test "carries the title, the exact page macros, the url and base hashtags" do
      caption = MealPlanShareText.image_caption(plan(), opts())

      assert caption =~ "Anti-inflammatory week · Oct 5"
      # Same rounding the page's macro tiles use (whole floats become ints).
      assert caption =~ "~1850 kcal/day"
      assert caption =~ "95g protein"
      assert caption =~ "180.4g carbs"
      assert caption =~ "60g fat"
      assert caption =~ @url
      assert caption =~ "#mealprep"
      assert caption =~ "#nutrition"
    end

    test "includes a goal hashtag derived from the goal label" do
      assert MealPlanShareText.image_caption(plan(), opts()) =~ "#antiinflammatory"
    end

    test "omits the goal hashtag when there is no goal label" do
      caption = MealPlanShareText.image_caption(plan(%{goal_label: nil}), opts())
      refute caption =~ "#antiinflammatory"
      assert caption =~ "#mealprep"
    end
  end

  describe "text_post/2" do
    test "lists one line per non-empty day and omits empty days" do
      post = MealPlanShareText.text_post(plan(), opts())

      assert post =~ "Monday: Lentil Soup · Grilled Salmon"
      assert post =~ "Wednesday: Spinach"
      # Tuesday has no meals — it must not appear.
      refute post =~ "Tuesday"
    end

    test "includes the recipe count, macro line, url and text hashtags" do
      post = MealPlanShareText.text_post(plan(), opts())

      assert post =~ "3 recipes"
      assert post =~ "~1850 kcal/day"
      assert post =~ "95g protein avg"
      assert post =~ @url
      assert post =~ "#whatieatinaweek"
    end

    test "resolves ingredient titles through the by-id localization map" do
      post =
        MealPlanShareText.text_post(
          plan(),
          opts(ingredient_names_by_id: %{7 => "Σπανάκι"}, locale: "el")
        )

      assert post =~ "Σπανάκι"
      refute post =~ "Spinach"
    end
  end

  describe "localization" do
    test "renders Greek weekday labels for an el plan" do
      post = MealPlanShareText.text_post(plan(%{locale: "el"}), opts(locale: "el"))

      # Δευτέρα = Monday, Τετάρτη = Wednesday
      assert post =~ "Δευτέρα"
      assert post =~ "Τετάρτη"
      refute post =~ "Monday"
    end
  end
end
