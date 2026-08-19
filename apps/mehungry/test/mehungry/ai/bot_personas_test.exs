defmodule Mehungry.AI.BotPersonasTest do
  use Mehungry.DataCase, async: true

  import Mehungry.{FoodFixtures, AccountsFixtures}

  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.{AiBotRecipe, RecipeSetup}

  defp persona_fixture(attrs \\ %{}) do
    {:ok, persona} =
      attrs
      |> Enum.into(%{
        name: "Persona #{System.unique_integer([:positive])}",
        voice_prompt: "You are a warm village grandmother."
      })
      |> Bot.create_persona()

    persona
  end

  defp setup_fixture(attrs \\ %{}) do
    {:ok, setup} =
      attrs
      |> Enum.into(%{name: "Setup #{System.unique_integer([:positive])}"})
      |> Bot.create_recipe_setup()

    setup
  end

  defp config_fixture(attrs) do
    user = user_fixture()

    {:ok, config} =
      attrs
      |> Enum.into(%{month: 9, year: 2026, bot_user_id: user.id, theme: "Autumn"})
      |> Bot.create_bot_config()

    config
  end

  describe "personas" do
    test "create + list" do
      persona = persona_fixture(%{name: "Grandma", uses_hashtags: false})
      assert persona.id
      assert Enum.any?(Bot.list_personas(), &(&1.id == persona.id))
    end

    test "voice_prompt is required" do
      assert {:error, changeset} = Bot.create_persona(%{name: "X"})
      assert %{voice_prompt: _} = errors_on(changeset)
    end
  end

  describe "recipe setups + seed ingredients" do
    test "add seed ingredients and build_brief groups them by role" do
      persona = persona_fixture()
      setup = setup_fixture(%{persona_id: persona.id, origin: "Crete", story: "From the hills."})

      oil = ingredient_fixture(%{name: "olive oil"})
      basil = ingredient_fixture(%{name: "basil"})
      shrimp = ingredient_fixture(%{name: "shrimp"})

      {:ok, _} =
        Bot.add_setup_ingredient(%{
          recipe_setup_id: setup.id,
          ingredient_id: oil.id,
          role: "primary"
        })

      {:ok, _} =
        Bot.add_setup_ingredient(%{
          recipe_setup_id: setup.id,
          ingredient_id: basil.id,
          role: "garnish"
        })

      {:ok, _} =
        Bot.add_setup_ingredient(%{
          recipe_setup_id: setup.id,
          ingredient_id: shrimp.id,
          role: "avoid"
        })

      assert length(Bot.list_setup_ingredients(setup.id)) == 3

      brief = Bot.build_brief(Bot.get_recipe_setup(setup.id))
      assert brief[:origin] == "Crete"
      assert brief[:story] == "From the hills."
      assert brief[:persona].id == persona.id
      assert brief[:seed_ingredients]["primary"] == ["olive oil"]
      assert brief[:seed_ingredients]["garnish"] == ["basil"]
      assert brief[:seed_ingredients]["avoid"] == ["shrimp"]
    end

    test "adding the same ingredient+role twice is idempotent" do
      setup = setup_fixture()
      oil = ingredient_fixture(%{name: "olive oil"})

      {:ok, _} =
        Bot.add_setup_ingredient(%{
          recipe_setup_id: setup.id,
          ingredient_id: oil.id,
          role: "primary"
        })

      {:ok, _} =
        Bot.add_setup_ingredient(%{
          recipe_setup_id: setup.id,
          ingredient_id: oil.id,
          role: "primary"
        })

      assert length(Bot.list_setup_ingredients(setup.id)) == 1
    end

    test "build_brief/1 returns nil when there is no setup" do
      assert Bot.build_brief(nil) == nil
    end
  end

  describe "get_context_for_date/2 setup cascade" do
    test "day override beats week override beats config" do
      config_setup = setup_fixture(%{name: "config-setup"})
      week_setup = setup_fixture(%{name: "week-setup"})
      day_setup = setup_fixture(%{name: "day-setup"})

      config = config_fixture(%{recipe_setup_id: config_setup.id})
      date = ~D[2026-09-03]

      # config only
      assert Bot.get_context_for_date(config, date).setup.id == config_setup.id

      # week override (day 3 → week 1)
      {:ok, _} =
        Bot.upsert_week_config(%{
          bot_config_id: config.id,
          week_number: 1,
          theme: "W",
          recipe_setup_id: week_setup.id
        })

      assert Bot.get_context_for_date(config, date).setup.id == week_setup.id

      # day override wins
      {:ok, _} =
        Bot.upsert_day_config(%{
          bot_config_id: config.id,
          date: date,
          focus_hint: "F",
          recipe_setup_id: day_setup.id
        })

      assert Bot.get_context_for_date(config, date).setup.id == day_setup.id
    end

    test "no setup anywhere yields nil" do
      config = config_fixture(%{})
      assert Bot.get_context_for_date(config, ~D[2026-09-10]).setup == nil
    end
  end

  describe "AiBotRecipe order rows" do
    test "an order row is valid with a nil bot_config_id" do
      setup = setup_fixture()
      user = user_fixture()

      {:ok, order} =
        Bot.create_recipe_order(%{recipe_setup_id: setup.id, bot_user_id: user.id, quantity: 3})

      recipe = recipe_fixture(user)

      assert {:ok, bot_recipe} =
               Bot.create_bot_recipe(%{
                 recipe_id: recipe.id,
                 recipe_order_id: order.id,
                 meal_type: "lunch",
                 scheduled_date: Date.utc_today(),
                 status: "pending_review"
               })

      assert bot_recipe.recipe_order_id == order.id
      assert is_nil(bot_recipe.bot_config_id)
    end

    test "a row with neither config nor order is rejected" do
      user = user_fixture()
      recipe = recipe_fixture(user)

      changeset =
        AiBotRecipe.changeset(%AiBotRecipe{}, %{
          recipe_id: recipe.id,
          meal_type: "lunch",
          scheduled_date: Date.utc_today()
        })

      refute changeset.valid?
      assert %{bot_config_id: _} = errors_on(changeset)
    end
  end

  describe "populate_setup_ingredients_from_condition/1" do
    test "no-op without a condition" do
      assert {:ok, 0} =
               Bot.populate_setup_ingredients_from_condition(%RecipeSetup{condition_id: nil})
    end
  end

  test "recipe order quantity is bounded" do
    setup = setup_fixture()
    user = user_fixture()

    assert {:error, changeset} =
             Bot.create_recipe_order(%{
               recipe_setup_id: setup.id,
               bot_user_id: user.id,
               quantity: 0
             })

    assert %{quantity: _} = errors_on(changeset)
  end
end
