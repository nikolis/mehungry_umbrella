defmodule Mehungry.ObanWorkers.RecipePublishWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.AI.Bot
  alias Mehungry.ObanWorkers.RecipePublishWorker

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :publisher_stub) end)

    user = user_fixture()
    recipe = recipe_fixture(user)

    {:ok, config} =
      Bot.create_bot_config(%{
        theme: "summer",
        month: 7,
        year: 2026,
        bot_user_id: user.id,
        publish_times: %{"dinner" => %{"En" => "18:00"}}
      })

    {:ok, bot_recipe} =
      Bot.create_bot_recipe(%{
        recipe_id: recipe.id,
        bot_config_id: config.id,
        meal_type: "dinner",
        scheduled_date: ~D[2026-07-19],
        status: "approved"
      })

    %{user: user, recipe: recipe, config: config, bot_recipe: bot_recipe}
  end

  defp stub_publisher(test_pid, results) do
    Application.put_env(:mehungry, :publisher_stub, fn _recipe, _user, _id, _lang, opts ->
      send(test_pid, {:publish_recipe, opts})
      results
    end)
  end

  defp ok_log(bot_recipe, platform) do
    {:ok, _} =
      Bot.create_post_log(%{
        ai_bot_recipe_id: bot_recipe.id,
        platform: platform,
        status: "ok",
        language_name: "En"
      })
  end

  test "returns :ok when every platform succeeds", %{bot_recipe: bot_recipe} do
    stub_publisher(self(), %{instagram: :ok, facebook: :ok, pinterest: :ok})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: bot_recipe.id,
               language_name: "En"
             })

    assert_received {:publish_recipe, %{"platforms" => ["instagram", "facebook", "pinterest"]}}
  end

  test "returns {:error, _} when a platform fails, so Oban retries", %{bot_recipe: bot_recipe} do
    stub_publisher(self(), %{instagram: {:error, "HTTP 400"}, facebook: :ok, pinterest: :skipped})

    assert {:error, message} =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: bot_recipe.id,
               language_name: "En"
             })

    assert message =~ "instagram"
  end

  test "excludes platforms that already have an ok post log", %{bot_recipe: bot_recipe} do
    ok_log(bot_recipe, "facebook")
    ok_log(bot_recipe, "pinterest")
    stub_publisher(self(), %{instagram: :ok})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: bot_recipe.id,
               language_name: "En"
             })

    assert_received {:publish_recipe, %{"platforms" => ["instagram"]}}
  end

  test "does not call the publisher when everything already succeeded", %{bot_recipe: bot_recipe} do
    for platform <- ["instagram", "facebook", "pinterest"], do: ok_log(bot_recipe, platform)
    stub_publisher(self(), %{})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: bot_recipe.id,
               language_name: "En"
             })

    refute_received {:publish_recipe, _}
  end

  test "force re-publishes platforms that already succeeded", %{bot_recipe: bot_recipe} do
    for platform <- ["instagram", "facebook", "pinterest"], do: ok_log(bot_recipe, platform)
    stub_publisher(self(), %{instagram: :ok, facebook: :ok, pinterest: :ok})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: bot_recipe.id,
               language_name: "En",
               platforms: ["instagram", "facebook", "pinterest"],
               force: true
             })

    assert_received {:publish_recipe, %{"platforms" => ["instagram", "facebook", "pinterest"]}}
  end

  test "publishes an ad-hoc order recipe that has no bot_config", %{user: user, recipe: recipe} do
    {:ok, setup} = Bot.create_recipe_setup(%{name: "Grandma from Crete"})

    {:ok, order} =
      Bot.create_recipe_order(%{
        recipe_setup_id: setup.id,
        bot_user_id: user.id,
        quantity: 1,
        language_name: "En"
      })

    {:ok, order_recipe} =
      Bot.create_bot_recipe(%{
        recipe_id: recipe.id,
        recipe_order_id: order.id,
        meal_type: "dinner",
        scheduled_date: ~D[2026-07-19],
        status: "approved"
      })

    # An ok log for the order's language stands in for what the (stubbed)
    # publisher would write, so maybe_mark_published can flip the status.
    ok_log(order_recipe, "instagram")
    stub_publisher(self(), %{instagram: :ok, facebook: :ok, pinterest: :ok})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: order_recipe.id,
               language_name: "En",
               force: true
             })

    assert_received {:publish_recipe, %{"platforms" => ["instagram", "facebook", "pinterest"]}}
    assert Bot.get_bot_recipe!(order_recipe.id).status == "published"
  end

  test "skips unapproved recipes without calling the publisher", %{
    recipe: recipe,
    config: config
  } do
    {:ok, pending} =
      Bot.create_bot_recipe(%{
        recipe_id: recipe.id,
        bot_config_id: config.id,
        meal_type: "lunch",
        scheduled_date: ~D[2026-07-19],
        status: "pending_review"
      })

    stub_publisher(self(), %{})

    assert :ok =
             perform_job(RecipePublishWorker, %{
               ai_bot_recipe_id: pending.id,
               language_name: "En"
             })

    refute_received {:publish_recipe, _}
  end
end
