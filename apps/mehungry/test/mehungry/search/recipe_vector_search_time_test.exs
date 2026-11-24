defmodule Mehungry.Search.RecipeVectorSearchTimeTest do
  @moduledoc "The `:max_total_minutes` / `:time_exempt_roles` search filters + `total_minutes`."
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.EmbeddingClientStub
  alias Mehungry.Food
  alias Mehungry.Food.{MealRoleAssignments, Recipe}
  alias Mehungry.Repo
  alias Mehungry.Search.RecipeVectorSearch

  setup do
    user = user_fixture()

    %{
      user: user,
      omelette: seeded(user, "Quick omelette eggs", 5, 7, []),
      porridge: seeded(user, "Slow porridge eggs", 10, 30, []),
      untimed: seeded(user, "Untimed eggs scramble", nil, nil, []),
      frittata: seeded(user, "Baked frittata eggs dinner", 20, 45, ["dinner"])
    }
  end

  defp seeded(user, title, prep, cook, roles) do
    recipe = recipe_fixture(user, %{title: title})
    vector = Pgvector.new(EmbeddingClientStub.vector(title))

    Repo.update_all(from(r in Recipe, where: r.id == ^recipe.id),
      set: [
        embedding: vector,
        preperation_time_lower_limit: prep,
        cooking_time_lower_limit: cook
      ]
    )

    if roles != [] do
      MealRoleAssignments.apply_ai_roles(
        recipe.id,
        Enum.map(roles, &%{role: &1, confidence: 0.9})
      )
    end

    Repo.get!(Recipe, recipe.id)
  end

  defp search(ctx, opts),
    do: RecipeVectorSearch.search("eggs", [user_id: ctx.user.id] ++ opts)

  test "Food.total_time_minutes/1 sums prep + cook, nil when unknown", ctx do
    assert Food.total_time_minutes(ctx.omelette) == 12
    assert Food.total_time_minutes(ctx.porridge) == 40
    assert Food.total_time_minutes(ctx.untimed) == nil
  end

  test "results carry total_minutes", ctx do
    by_id = ctx |> search([]) |> Map.new(&{&1.id, &1.total_minutes})
    assert by_id[ctx.omelette.id] == 12
    assert by_id[ctx.untimed.id] == nil
  end

  test ":max_total_minutes keeps only known, short-enough recipes", ctx do
    found = ctx |> search(max_total_minutes: 15) |> MapSet.new(& &1.id)

    assert MapSet.member?(found, ctx.omelette.id)
    refute MapSet.member?(found, ctx.porridge.id)
    refute MapSet.member?(found, ctx.untimed.id)
    refute MapSet.member?(found, ctx.frittata.id)

    found = ctx |> search(max_total_minutes: 40) |> MapSet.new(& &1.id)
    assert MapSet.member?(found, ctx.porridge.id)
  end

  test ":time_exempt_roles lets a role through whatever its time", ctx do
    found =
      ctx
      |> search(max_total_minutes: 40, time_exempt_roles: ["dinner"])
      |> MapSet.new(& &1.id)

    assert MapSet.member?(found, ctx.frittata.id)
    assert MapSet.member?(found, ctx.porridge.id)
    refute MapSet.member?(found, ctx.untimed.id)
  end
end
