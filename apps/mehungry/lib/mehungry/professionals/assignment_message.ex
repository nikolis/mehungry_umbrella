defmodule Mehungry.Professionals.AssignmentMessage do
  @moduledoc """
  One message in the single running conversation between a nutritionist and a
  client (the `TutorClientAssignment` relationship — one thread per
  professional↔client pair). `sender_user_id` is whichever of the two wrote it;
  the recipient is the other party. A message is unread for its recipient while
  `read_at` is nil.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_body 4000

  schema "assignment_messages" do
    field :body, :string
    field :read_at, :utc_datetime

    belongs_to :professional, Mehungry.Accounts.User
    belongs_to :client, Mehungry.Accounts.User
    belongs_to :sender, Mehungry.Accounts.User, foreign_key: :sender_user_id

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:professional_id, :client_id, :sender_user_id, :body, :read_at])
    |> update_change(:body, &trim/1)
    |> validate_required([:professional_id, :client_id, :sender_user_id, :body])
    |> validate_length(:body, max: @max_body)
    |> foreign_key_constraint(:professional_id)
    |> foreign_key_constraint(:client_id)
    |> foreign_key_constraint(:sender_user_id)
  end

  defp trim(body) when is_binary(body) do
    case String.trim(body) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(body), do: body
end
