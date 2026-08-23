defmodule Mehungry.Food.HashtagReconciliation do
  @moduledoc """
  Tracks the reconciliation of a single recipe's hashtags through the admin
  reconciliation sweep. `status` is the lifecycle of one recipe:

    * `pending`    — enqueued, not yet picked up
    * `processing` — a `HashtagReconciliationWorker` job is reconciling it
    * `completed`  — `Recipes.ensure_recipe_hashtags/1` ran; `tags_added` holds
                     how many hashtag links it created
    * `failed`     — reconciliation raised/failed; `error` holds the reason

  Driven by `Mehungry.Food.HashtagReconciliations`. Modelled on
  `Mehungry.FoodData.Usda.SeedFile`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "hashtag_reconciliations" do
    field :status, :string, default: "pending"
    field :tags_added, :integer
    field :error, :string
    field :completed_at, :utc_datetime

    belongs_to :recipe, Mehungry.Food.Recipe

    timestamps()
  end

  def changeset(reconciliation, attrs) do
    reconciliation
    |> cast(attrs, [:recipe_id, :status, :tags_added, :error, :completed_at])
    |> validate_required([:recipe_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:recipe_id)
  end
end
