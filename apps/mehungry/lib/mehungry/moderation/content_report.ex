defmodule Mehungry.Moderation.ContentReport do
  @moduledoc """
  A user's report against a piece of user-generated content — a recipe, a
  comment, or a user (their profile). Reviewed by the admin in
  `/professional/moderation`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  @target_types ~w(recipe comment user)
  @reasons ~w(spam harassment sexual dangerous_advice other)
  @statuses ~w(open dismissed actioned)
  @resolutions ~w(none content_removed account_removed)

  schema "content_reports" do
    field :target_type, :string
    field :target_id, :integer
    field :reason, :string
    field :note, :string
    field :snapshot, :string
    field :status, :string, default: "open"
    field :resolution, :string
    field :admin_note, :string
    field :resolved_at, :naive_datetime

    belongs_to :reporter, User
    belongs_to :target_user, User

    timestamps()
  end

  def target_types, do: @target_types
  def reasons, do: @reasons
  def statuses, do: @statuses

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :reporter_id,
      :target_type,
      :target_id,
      :target_user_id,
      :reason,
      :note,
      :snapshot
    ])
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:reporter_id, :target_type, :target_id, :reason])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:reason, @reasons)
    |> validate_length(:note, max: 1000)
    |> unique_constraint([:reporter_id, :target_type, :target_id],
      name: :content_reports_open_unique_index
    )
  end

  @doc false
  def resolve_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolution, :admin_note, :resolved_at])
    |> validate_required([:status, :resolution, :resolved_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:resolution, @resolutions)
    |> validate_length(:admin_note, max: 2000)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
