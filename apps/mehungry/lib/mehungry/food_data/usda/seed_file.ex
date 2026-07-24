defmodule Mehungry.FoodData.Usda.SeedFile do
  @moduledoc """
  Tracks the seeding of a single S3 object (`bucket` + `key`) through the USDA
  ingredient importer. `status` is the lifecycle of one file:

    * `pending`    — enqueued, not yet picked up
    * `processing` — a `SeedFileImportWorker` job is parsing it
    * `completed`  — parsed and inserted; `ingredient_count` holds the count
    * `failed`     — parse/fetch failed; `error` holds the inspected reason

  Driven by `Mehungry.FoodData.Usda.SeedFiles`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "seed_files" do
    field :bucket, :string
    field :key, :string
    field :status, :string, default: "pending"
    field :ingredient_count, :integer
    field :error, :string
    field :completed_at, :utc_datetime

    timestamps()
  end

  def changeset(seed_file, attrs) do
    seed_file
    |> cast(attrs, [:bucket, :key, :status, :ingredient_count, :error, :completed_at])
    |> validate_required([:bucket, :key, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:bucket, :key])
  end
end
