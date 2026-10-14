defmodule Mehungry.BetaSignups.BetaInviteSend do
  @moduledoc """
  A record that a given Android beta `version` was sent to a given tester.
  Powers the "which version went to which tester" history and the
  "testers missing the current version" recipient filter.

  `beta_signup_id` is nullable — invites can also go to ad-hoc addresses or a
  Google Group that aren't rows in `beta_signups`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "beta_invite_sends" do
    field :email, :string
    field :canonical_email, :string
    field :version, :string
    field :status, :string, default: "ok"

    belongs_to :beta_signup, Mehungry.BetaSignups.BetaSignup

    timestamps(updated_at: false)
  end

  def changeset(send, attrs) do
    send
    |> cast(attrs, [:email, :version, :status, :beta_signup_id])
    |> update_change(:email, &String.trim/1)
    |> update_change(:version, &String.trim/1)
    |> validate_required([:email, :version])
    |> put_canonical_email()
  end

  defp put_canonical_email(changeset) do
    case get_field(changeset, :email) do
      email when is_binary(email) ->
        put_change(changeset, :canonical_email, User.canonical_email(email))

      _ ->
        changeset
    end
  end
end
