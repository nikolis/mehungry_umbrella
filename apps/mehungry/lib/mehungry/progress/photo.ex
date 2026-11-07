defmodule Mehungry.Progress.Photo do
  @moduledoc """
  A body photo attached to a `Progress.Entry` (so it is pinned to that entry's
  date on the trend chart and usable in the before→now comparison). The object
  lives in `Mehungry.Storage`; deleting a photo must delete the storage object
  too (the FK cascade only removes rows).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "progress_photos" do
    field :url, :string
    field :storage_key, :string
    field :position, :integer, default: 0
    field :caption, :string

    belongs_to :entry, Mehungry.Progress.Entry, foreign_key: :progress_entry_id
    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:progress_entry_id, :user_id, :url, :storage_key, :position, :caption])
    |> validate_required([:progress_entry_id, :user_id, :url])
    |> foreign_key_constraint(:progress_entry_id)
    |> foreign_key_constraint(:user_id)
  end
end
