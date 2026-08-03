defmodule Mehungry.Health.ConditionSeeder do
  @moduledoc """
  Idempotent seed set for the `Mehungry.Health` condition registry.

  Loads the bundled catalogue at
  `priv/repo/seeds/data/health_conditions.json` (one object per condition:
  `main_name`, `synonyms`, `category`, `subcategory`, `description`) and upserts
  each row keyed on the unique `name`. Safe to run repeatedly — an existing
  condition has its mutable fields refreshed (`on_conflict: :replace`), so
  re-seeding picks up catalogue edits without creating duplicates.

  This seeds *conditions only* (the reference registry). It asserts no
  `CompoundRecommendation` advice — those stay curated (seeds.exs / the admin
  view) since they require a resolved compound.

  Invoked from `priv/repo/seeds.exs`; also runnable standalone:

      Mehungry.Health.ConditionSeeder.seed()
  """

  import Ecto.Query, only: [from: 2]

  alias Mehungry.Repo
  alias Mehungry.Health.Condition

  @relative_path "repo/seeds/data/health_conditions.json"

  @replaceable [:synonyms, :category, :subcategory, :description, :updated_at]

  @doc """
  Seed the condition registry from the bundled catalogue.

  Returns `{:ok, %{inserted: n, total: t}}` where `inserted` counts rows that
  were newly created on this run.
  """
  def seed(path \\ default_path()) do
    rows = path |> File.read!() |> Jason.decode!()

    before = Repo.aggregate(Condition, :count, :id)

    Enum.each(rows, &upsert/1)

    total = Repo.aggregate(Condition, :count, :id)
    {:ok, %{inserted: total - before, total: total}}
  end

  @doc "Absolute path to the bundled catalogue inside the app's `priv` dir."
  def default_path do
    Application.app_dir(:mehungry, Path.join("priv", @relative_path))
  end

  defp upsert(row) do
    attrs = %{
      name: row["main_name"],
      synonyms: row["synonyms"] || [],
      category: row["category"],
      subcategory: row["subcategory"],
      description: row["description"]
    }

    %Condition{}
    |> Condition.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @replaceable},
      conflict_target: :name,
      returning: false
    )
  end

  @doc "Count of conditions currently in the registry — a quick post-seed check."
  def count, do: Repo.one(from(c in Condition, select: count(c.id)))
end
