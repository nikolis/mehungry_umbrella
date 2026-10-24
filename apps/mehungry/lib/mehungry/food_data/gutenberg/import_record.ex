defmodule Mehungry.FoodData.Gutenberg.ImportRecord do
  @moduledoc """
  Tracks the admin's manual review of a single Gutenberg recipe, so the
  one-at-a-time review flow can resume where it left off.

  The unit of work — the Gutenberg analogue of a MyPlate slug — is a **recipe
  reference** `ref`: `"<book_id>:<index>"` (e.g. `"6385:12"`, the 12th parsed
  recipe of ebook 6385). `status`:

    * `completed` — the recipe was saved via the review form; `recipe_id` points
                    at the created recipe
    * `skipped`   — the admin passed on it ("pass for now")

  A ref with no row has not been reviewed yet. Driven by
  `Mehungry.FoodData.Gutenberg.Imports`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(completed skipped)

  schema "gutenberg_imports" do
    field :ref, :string
    field :status, :string, default: "pending"
    field :unmatched_count, :integer
    field :error, :string
    field :completed_at, :utc_datetime

    belongs_to :recipe, Mehungry.Food.Recipe

    timestamps()
  end

  def changeset(import_record, attrs) do
    import_record
    |> cast(attrs, [:ref, :status, :recipe_id, :unmatched_count, :error, :completed_at])
    |> validate_required([:ref, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:ref)
  end
end
