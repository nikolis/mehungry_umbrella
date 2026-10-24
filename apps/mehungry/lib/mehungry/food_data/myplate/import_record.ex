defmodule Mehungry.FoodData.MyPlate.ImportRecord do
  @moduledoc """
  Tracks the admin's manual review of a single MyPlate recipe slug, so the
  one-at-a-time review flow can resume where it left off. `status` records the
  outcome of a review:

    * `completed` — the recipe was saved via the review form; `recipe_id` points
                    at the created recipe
    * `skipped`   — the admin passed on it ("pass for now")

  A slug with no row has not been reviewed yet. Driven by
  `Mehungry.FoodData.MyPlate.Imports`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(completed skipped)

  schema "myplate_imports" do
    field :slug, :string
    field :status, :string, default: "pending"
    field :unmatched_count, :integer
    field :error, :string
    field :completed_at, :utc_datetime

    belongs_to :recipe, Mehungry.Food.Recipe

    timestamps()
  end

  def changeset(import_record, attrs) do
    import_record
    |> cast(attrs, [:slug, :status, :recipe_id, :unmatched_count, :error, :completed_at])
    |> validate_required([:slug, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end
end
