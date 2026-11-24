defmodule Mehungry.Search.RecipeVectorSearchRankedTest do
  @moduledoc "The `:ranked_for_user` search: own → saved → public, with a public reserve."
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.EmbeddingClientStub
  alias Mehungry.Accounts.UserContent
  alias Mehungry.Food.Recipe
  alias Mehungry.Repo
  alias Mehungry.Search.RecipeVectorSearch

  defp seeded(owner, title, opts \\ []) do
    recipe = recipe_fixture(owner, %{title: title})

    Repo.update_all(from(r in Recipe, where: r.id == ^recipe.id),
      set: [
        embedding: Pgvector.new(EmbeddingClientStub.vector(title)),
        private: Keyword.get(opts, :private, false)
      ]
    )

    recipe
  end

  defp search(user, limit),
    do: RecipeVectorSearch.search("lentil soup", ranked_for_user: user.id, limit: limit)

  test "orders own, then saved, then public, and never returns another user's private recipe" do
    me = user_fixture()
    other = user_fixture()

    own = seeded(me, "own lentil soup")
    saved = seeded(other, "saved lentil soup")
    public = seeded(other, "public lentil soup")
    private = seeded(other, "private lentil soup", private: true)
    {:ok, _} = UserContent.save_user_recipe(me.id, saved.id)

    results = search(me, 20)

    assert Enum.map(results, &{&1.id, &1.source}) ==
             [{own.id, "own"}, {saved.id, "saved"}, {public.id, "public"}]

    refute private.id in Enum.map(results, & &1.id)
  end

  test "a large own catalog still leaves room for public recipes" do
    me = user_fixture()
    other = user_fixture()

    for i <- 1..10, do: seeded(me, "own lentil soup #{i}")
    for i <- 1..10, do: seeded(other, "public lentil soup #{i}")

    results = search(me, 8)

    assert length(results) == 8
    assert Enum.count(results, &(&1.source == "own")) == 3
    assert Enum.count(results, &(&1.source == "public")) == 5
    # Tier order holds: every own result precedes every public one.
    assert Enum.map(results, & &1.source) ==
             List.duplicate("own", 3) ++ List.duplicate("public", 5)
  end

  test "public slots the public tier can't fill go back to own recipes" do
    me = user_fixture()
    other = user_fixture()

    for i <- 1..10, do: seeded(me, "own lentil soup #{i}")
    seeded(other, "public lentil soup")

    results = search(me, 8)

    assert length(results) == 8
    assert Enum.count(results, &(&1.source == "public")) == 1
    assert Enum.count(results, &(&1.source == "own")) == 7
    assert List.last(results).source == "public"
  end
end
