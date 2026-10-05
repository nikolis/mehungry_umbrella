defmodule Mehungry.Health.ConditionSeeder do
  @moduledoc """
  Idempotent seed set for the `Mehungry.Health` condition registry.

  Loads the bundled catalogue at
  `priv/repo/seeds/data/health_conditions.json` (one object per condition:
  `main_name`, `synonyms`, `category`, `subcategory`, `description`, and an optional
  `states` array of disease phases) and upserts each row keyed on the unique `name`.
  Safe to run repeatedly — an existing condition has its mutable fields refreshed
  (`on_conflict: :replace`), so re-seeding picks up catalogue edits without creating
  duplicates. A condition's `states` (e.g. Ulcerative Colitis → Active Flare /
  Remission) are upserted on `(condition_id, slug)`.

  This seeds *conditions only* (the reference registry). It asserts no
  `CompoundRecommendation` advice — those stay curated (seeds.exs / the admin
  view) since they require a resolved compound.

  Invoked from `priv/repo/seeds.exs`; also runnable standalone:

      Mehungry.Health.ConditionSeeder.seed()
  """

  import Ecto.Query, only: [from: 2]

  alias Mehungry.Repo
  alias Mehungry.Health.{Condition, ConditionState}

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
    # Second pass: link each row's optional `parent` (by name) now that every
    # condition exists, so order within the catalogue doesn't matter.
    resolve_parents(rows)

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

    upsert_states(row)
  end

  # Upsert the condition's disease-state phases (if any), keyed on `(condition_id, slug)`.
  # The condition insert above uses `returning: false`, so re-fetch it by its unique name.
  defp upsert_states(%{"main_name" => name, "states" => states})
       when is_list(states) and states != [] do
    condition = Repo.one!(from(c in Condition, where: c.name == ^name))

    Enum.each(states, fn s ->
      %ConditionState{}
      |> ConditionState.changeset(%{
        condition_id: condition.id,
        name: s["name"],
        slug: s["slug"],
        is_default: s["is_default"] || false,
        position: s["position"] || 0,
        description: s["description"]
      })
      |> Repo.insert(
        on_conflict: {:replace, [:name, :is_default, :position, :description, :updated_at]},
        conflict_target: [:condition_id, :slug],
        returning: false
      )
    end)
  end

  defp upsert_states(_row), do: :ok

  # Set `parent_condition_id` for any row carrying a `"parent"` name, resolving the
  # parent by its unique name. Idempotent — re-seeding just re-asserts the link.
  defp resolve_parents(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Enum.each(rows, fn
      %{"main_name" => name, "parent" => parent} when is_binary(parent) and parent != "" ->
        with %Condition{id: child_id} <- Repo.get_by(Condition, name: name),
             %Condition{id: parent_id} <- Repo.get_by(Condition, name: parent) do
          from(c in Condition, where: c.id == ^child_id)
          |> Repo.update_all(set: [parent_condition_id: parent_id, updated_at: now])
        end

      _ ->
        :ok
    end)
  end

  @doc "Count of conditions currently in the registry — a quick post-seed check."
  def count, do: Repo.one(from(c in Condition, select: count(c.id)))
end
