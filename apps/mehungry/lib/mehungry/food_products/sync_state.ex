defmodule Mehungry.FoodProducts.SyncState do
  @moduledoc """
  Watermark row for Open Food Facts synchronization. One row per sync kind
  (key `"delta"` for the weekly delta worker); `last_processed_file` is the
  newest OFF delta filename already applied.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "off_sync_state" do
    field :key, :string
    field :last_processed_file, :string
    field :last_synced_at, :utc_datetime
    field :products_upserted, :integer, default: 0

    timestamps()
  end

  def changeset(sync_state, attrs) do
    sync_state
    |> cast(attrs, [:key, :last_processed_file, :last_synced_at, :products_upserted])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
