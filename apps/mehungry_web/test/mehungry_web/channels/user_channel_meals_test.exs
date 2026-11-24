defmodule MehungryWeb.UserChannelMealsTest do
  @moduledoc """
  A calendar written from elsewhere (a nutritionist's draft, an AI plan) pokes the
  owner's connected mobile client so it refetches — and nobody else's.
  """
  use MehungryWeb.ChannelCase, async: false

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.History

  setup do
    user = user_fixture()

    {:ok, _, socket} =
      MehungryWeb.UserSocket
      |> socket("user_socket:#{user.id}", %{user_id: user.id})
      |> subscribe_and_join(MehungryWeb.UserChannel, "user:#{user.id}")

    # The subscription happens in :after_join; a sync call lets it finish.
    :sys.get_state(socket.channel_pid)

    %{user: user}
  end

  test "a plan written to the calendar pushes meals_changed to its owner", %{user: user} do
    recipe = recipe_fixture(user, %{title: "poke test recipe"})

    entry = %{
      day_index: 1,
      meal_type: "lunch",
      recipe_id: recipe.id,
      cooking_portions: 1,
      ingredient_id: nil,
      quantity: nil,
      measurement_unit_id: nil,
      ingredient_portion_id: nil
    }

    assert {:ok, [_meal], 0} =
             MealPlanGenerator.persist_entries_to_calendar([entry], user.id, ~D[2030-01-07])

    assert_push "meals_changed", %{}
  end

  test "an empty write, or another user's calendar, pushes nothing", %{user: user} do
    assert {:ok, [], 0} =
             MealPlanGenerator.persist_entries_to_calendar([], user.id, ~D[2030-01-07])

    History.broadcast_meals_changed(user_fixture().id)

    refute_push "meals_changed", _
  end
end
