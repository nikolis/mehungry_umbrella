defmodule Mehungry.Progress.Photo do
  @moduledoc """
  A body photo attached to a `Progress.Entry` (so it is pinned to that entry's
  date on the trend chart and usable in the before→now comparison). Sensitive
  media: the object lives in the **private** bucket of `Mehungry.Storage`
  (`bucket: :private`) under `storage_key`, and is served only through
  short-lived signed URLs (`Progress.photo_url/1`) — `url` is populated only on
  legacy rows from the public-bucket era (cleared by
  `mix progress.migrate_photos`). Deleting a photo must delete the storage
  object too (the FK cascade only removes rows).

  `share_token` is the opt-in, revocable public handle
  (`GET /shared/photos/:token`): set by `Progress.share_photo/2`, nulled by
  `unshare_photo/2`. Never cast from user attrs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "progress_photos" do
    field :url, :string
    field :storage_key, :string
    field :position, :integer, default: 0
    field :caption, :string
    field :share_token, :string
    field :shared_at, :utc_datetime

    belongs_to :entry, Mehungry.Progress.Entry, foreign_key: :progress_entry_id
    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:progress_entry_id, :user_id, :url, :storage_key, :position, :caption])
    |> validate_required([:progress_entry_id, :user_id])
    |> validate_location()
    |> foreign_key_constraint(:progress_entry_id)
    |> foreign_key_constraint(:user_id)
  end

  # A photo must be locatable: a private-bucket `storage_key` (the norm) or a
  # legacy public `url`.
  defp validate_location(changeset) do
    if get_field(changeset, :storage_key) || get_field(changeset, :url) do
      changeset
    else
      add_error(changeset, :storage_key, "can't be blank")
    end
  end
end
