defmodule Mehungry.BetaSignups.BetaSignup do
  @moduledoc """
  A public signup from the `/trial` page — someone who registered interest in
  joining the Android closed-testing programme. Stores only the email (plus a
  canonical form for dedupe and a random token for one-click unsubscribe).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  @platforms ~w(android ios web)

  @doc "The selectable platforms, in display order."
  def platforms, do: @platforms

  schema "beta_signups" do
    field :email, :string
    field :canonical_email, :string
    field :unsubscribe_token, :string
    field :source, :string
    field :platforms, {:array, :string}, default: @platforms

    timestamps()
  end

  def changeset(beta_signup, attrs) do
    beta_signup
    |> cast(attrs, [:email, :source, :platforms])
    |> update_change(:email, &String.trim/1)
    |> clean_platforms()
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_subset(:platforms, @platforms)
    |> validate_length(:platforms, min: 1, message: "select at least one platform")
    |> put_canonical_email()
    |> put_unsubscribe_token()
    |> unsafe_validate_unique(:canonical_email, Mehungry.Repo, message: "is already registered")
    |> unique_constraint(:canonical_email, message: "is already registered")
    |> unique_constraint(:unsubscribe_token)
  end

  # The checkbox group sends a hidden "" entry so the key is always present;
  # drop blanks and dedupe. Only touch the field when it was actually submitted
  # so programmatic creates keep the schema default ("all platforms").
  defp clean_platforms(changeset) do
    case get_change(changeset, :platforms) do
      nil ->
        changeset

      list ->
        put_change(changeset, :platforms, list |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq())
    end
  end

  # Reuse the same canonicalization the Accounts user changeset uses so gmail
  # aliases (dots / +tags) dedupe against existing signups.
  defp put_canonical_email(changeset) do
    case get_field(changeset, :email) do
      email when is_binary(email) ->
        put_change(changeset, :canonical_email, User.canonical_email(email))

      _ ->
        changeset
    end
  end

  defp put_unsubscribe_token(changeset) do
    if get_field(changeset, :unsubscribe_token) do
      changeset
    else
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      put_change(changeset, :unsubscribe_token, token)
    end
  end
end
