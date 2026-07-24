defmodule Mehungry.Accounts.User do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :canonical_email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime
    field :profile_pic, :string
    field :name, :string
    field :instagram_token, :map, default: %{}
    field :facebook_token, :map, default: %{}
    field :pinterest_token, :map, default: %{}

    has_one :recipes, Mehungry.Food.Recipe
    has_one :user_profile, Mehungry.Accounts.UserProfile

    timestamps()
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email()
    |> validate_password(opts)
  end

  def registration_3rd_party_changeset(user, attrs, _opts \\ []) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> cast(attrs, [:email, :profile_pic, :name])
    |> validate_email()
    |> put_change(:confirmed_at, now)
  end

  def tokens_changeset(user, attrs, _opts \\ []) do
    user
    |> cast(attrs, [:instagram_token, :facebook_token, :pinterest_token])
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> put_canonical_email()
    |> unsafe_validate_unique(:email, Mehungry.Repo)
    |> unique_constraint(:email)
    |> unsafe_validate_unique(:canonical_email, Mehungry.Repo,
      message: "has already been taken (an alias of this address already exists)"
    )
    |> unique_constraint(:canonical_email,
      message: "has already been taken (an alias of this address already exists)"
    )
  end

  defp put_canonical_email(changeset) do
    case get_field(changeset, :email) do
      email when is_binary(email) ->
        put_change(changeset, :canonical_email, canonical_email(email))

      _ ->
        changeset
    end
  end

  @doc """
  Canonicalizes an email address so that provider-specific aliases collapse to a
  single identity, closing the "one inbox, many accounts" abuse vector.

  Rules:

    * lowercased and trimmed
    * `gmail.com` / `googlemail.com` — every `.` in the local part is removed,
      everything from the first `+` is dropped, and the domain is normalized to
      `gmail.com` (Google routes all of these to the same inbox)
    * any other domain — only the `+tag` suffix is stripped (near-universal),
      dots are preserved
    * a string without a single `@` is returned lowercased/trimmed, unchanged

  ## Examples

      iex> canonical_email("R.uz.uf.i.w.owog8.21+promo@googlemail.com")
      "ruzufiwowog821@gmail.com"

      iex> canonical_email("Jane.Doe+news@outlook.com")
      "jane.doe@outlook.com"

  """
  def canonical_email(email) when is_binary(email) do
    downcased = email |> String.trim() |> String.downcase()

    case String.split(downcased, "@") do
      [local, domain] ->
        local = local |> String.split("+") |> hd()

        {local, domain} =
          if domain in ["gmail.com", "googlemail.com"] do
            {String.replace(local, ".", ""), "gmail.com"}
          else
            {local, domain}
          end

        "#{local}@#{domain}"

      _ ->
        downcased
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Mehungry.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
