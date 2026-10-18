defmodule Mehungry.WeeklyPlanShareTest do
  @moduledoc """
  Covers the core-side pieces of the shareable weekly-plan feature: the shared
  `NutrientUtils.macro_summary/1` (the single source of truth for the card's and
  the calendar's macro numbers) and the reference-less `WEEKLY_PLAN` post.
  """
  use Mehungry.DataCase

  alias Mehungry.{Food, NutrientUtils, Posts}

  import Mehungry.AccountsFixtures

  describe "NutrientUtils.macro_summary/1" do
    test "pulls macro grams by bucket and energy by name" do
      total = %{
        "Energy" => %{"amount" => 1800.0, "measurement_unit" => "kcal"},
        "Protein" => %{"amount" => 90.0, "measurement_unit" => "g"},
        "Total Fat" => %{"amount" => 60.0, "measurement_unit" => "g"},
        "Carbohydrate, By Difference" => %{"amount" => 200.0, "measurement_unit" => "g"},
        "Total Sugars" => %{"amount" => 40.0, "measurement_unit" => "g"},
        "Fiber, Total Dietary" => %{"amount" => 25.0, "measurement_unit" => "g"}
      }

      assert %{
               energy_kcal: 1800,
               protein_g: 90.0,
               fat_g: 60.0,
               carbs_g: 200.0,
               sugars_g: 40.0,
               fiber_g: 25.0
             } = NutrientUtils.macro_summary(total)
    end

    test "falls back to zeros for an empty map" do
      assert %{energy_kcal: 0, protein_g: p, fat_g: f, carbs_g: c} =
               NutrientUtils.macro_summary(%{})

      assert p == 0.0 and f == 0.0 and c == 0.0
    end

    test "pulls sodium and saturated fat from nested children, converting units" do
      # Saturated Fat is nested under Total Fat; Sodium under the Minerals umbrella
      # (NutrientHierarchyBuilder), so they aren't top-level keys like the macros.
      total = %{
        "Total Fat" => %{
          "amount" => 60.0,
          "measurement_unit" => "g",
          "children" => [
            %{"name" => "Saturated Fat", "amount" => 12.0, "measurement_unit" => "g"}
          ]
        },
        "Minerals" => %{
          "amount" => 0.0,
          "measurement_unit" => "g",
          "children" => [
            %{"name" => "Sodium, Na", "amount" => 1500.0, "measurement_unit" => "mg"}
          ]
        }
      }

      assert %{sodium_mg: 1500, saturated_fat_g: 12.0} = NutrientUtils.macro_summary(total)
    end

    test "sodium and saturated fat default to 0 when absent" do
      assert %{sodium_mg: 0, saturated_fat_g: +0.0} = NutrientUtils.macro_summary(%{})
    end
  end

  describe "weekly-plan post" do
    setup do
      user = user_fixture()

      {:ok, graphic} =
        Food.create_weekly_plan_graphic(%{
          user_id: user.id,
          week_start: ~D[2026-10-06],
          locale: "en",
          goal_label: "Anti-inflammatory",
          image_url: "https://example.com/card.png",
          macros: %{"energy_kcal" => 1900, "protein_g" => 112.0},
          caption: "A planned week · ~1900 kcal/day · 112 g protein avg"
        })

      %{user: user, graphic: graphic}
    end

    test "create_weekly_plan_post/2 inserts a reference-less WEEKLY_PLAN post", %{
      graphic: graphic
    } do
      assert {:ok, post} = Posts.create_weekly_plan_post(graphic, "My week · 6 Oct – 12 Oct")

      assert post.type_ == "WEEKLY_PLAN"
      assert is_nil(post.reference_id)
      assert post.weekly_plan_graphic_id == graphic.id
      assert post.user_id == graphic.user_id
      assert post.md_media_url == graphic.image_url
      assert post.description == graphic.caption
    end

    test "a WEEKLY_PLAN post requires its graphic (no silent reference-less insert)" do
      changeset =
        Mehungry.Posts.Post.changeset(%Mehungry.Posts.Post{}, %{
          type_: "WEEKLY_PLAN",
          title: "My week",
          md_media_url: "https://example.com/card.png"
        })

      refute changeset.valid?
      assert %{weekly_plan_graphic_id: _, user_id: _} = errors_on(changeset)
    end

    test "latest_weekly_plan_graphic/2 returns the newest card for the week, nil otherwise",
         %{user: user, graphic: graphic} do
      # Same week → the newest row wins (so the UI can show the saved card).
      {:ok, newer} =
        Food.create_weekly_plan_graphic(%{
          user_id: user.id,
          week_start: ~D[2026-10-06],
          image_url: "https://example.com/card-2.png"
        })

      assert Food.latest_weekly_plan_graphic(user.id, ~D[2026-10-06]).id == newer.id
      # (the first graphic from setup is older, same week)
      assert newer.id > graphic.id

      # A week with no card → nil.
      assert Food.latest_weekly_plan_graphic(user.id, ~D[2026-11-02]) == nil
    end

    test "a RECIPE post still requires reference_id" do
      changeset =
        Mehungry.Posts.Post.changeset(%Mehungry.Posts.Post{}, %{
          type_: "RECIPE",
          title: "A recipe",
          md_media_url: "https://example.com/r.png"
        })

      refute changeset.valid?
      assert %{reference_id: _} = errors_on(changeset)
    end
  end

  describe "comments on a WEEKLY_PLAN post" do
    setup do
      user = user_fixture()

      {:ok, graphic} =
        Food.create_weekly_plan_graphic(%{
          user_id: user.id,
          week_start: ~D[2026-10-06],
          image_url: "https://example.com/card.png"
        })

      {:ok, post} = Posts.create_weekly_plan_post(graphic, "My week · 6 Oct – 12 Oct")
      %{user: user, post: post}
    end

    test "create_post_comment/1 + list_post_comments/1 attach a comment to the post", %{
      user: user,
      post: post
    } do
      assert {:ok, comment} =
               Posts.create_post_comment(%{text: "Love this plan!", user_id: user.id, post_id: post.id})

      assert comment.post_id == post.id
      assert is_nil(comment.recipe_id)

      assert [loaded] = Posts.list_post_comments(post.id)
      assert loaded.id == comment.id
      assert loaded.text == "Love this plan!"
      # The author is preloaded for display.
      assert loaded.user.id == user.id
    end

    test "a comment with neither a recipe nor a post is rejected", %{user: user} do
      changeset = Mehungry.Posts.Comment.changeset(%Mehungry.Posts.Comment{}, %{
        text: "orphan",
        user_id: user.id
      })

      refute changeset.valid?
      assert %{recipe_id: _} = errors_on(changeset)
    end
  end
end
