defmodule Mehungry.Accounts.Auth do
  @moduledoc """
  Email/password authentication: registration, sessions, password change and
  reset, email change, and email confirmation.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{Admin, Profiles, User, UserNotifier, UserToken}

  @doc """
  Gets a user by email and password.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email) || Admin.get_user_by_canonical_email(email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Registers a user.
  """
  def register_user(attrs) do
    result =
      %User{}
      |> User.registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        Profiles.create_user_profile_if_needed(user)
        {:ok, user}

      _ ->
        result
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Managed (professional-created) accounts

  @doc """
  Creates a login-less "managed" client account on behalf of a professional.

  The account is pre-confirmed and has no password; the caller-supplied `attrs`
  should carry the display `name` (the alias) and the `managed_by_professional_id`.
  A synthetic, unique placeholder email is generated so the uniqueness invariants
  hold until the client claims the account.
  """
  def create_managed_client(attrs) do
    attrs = Map.put_new(attrs, :email, placeholder_email())

    result =
      %User{}
      |> User.managed_client_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        Profiles.create_user_profile_if_needed(user)
        {:ok, user}

      _ ->
        result
    end
  end

  defp placeholder_email do
    random = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    "managed-#{random}@clients.m3hungry.invalid"
  end

  @doc """
  Returns whether `user` is a managed account that has not yet been claimed
  (created by a professional, still without its own credentials).
  """
  def managed_unclaimed?(%User{managed_by_professional_id: pid, hashed_password: hp}),
    do: not is_nil(pid) and is_nil(hp)

  def managed_unclaimed?(_), do: false

  @doc """
  Builds and stores a claim token for a managed account, returning the encoded
  token to be embedded in a shareable claim URL. Any prior claim token for the
  user is revoked so only the latest link is valid.
  """
  def build_managed_client_claim_token(%User{} = user) do
    Repo.delete_all(UserToken.user_and_contexts_query(user, ["claim"]))
    {encoded_token, user_token} = UserToken.build_email_token(user, "claim")
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Returns the managed, unclaimed user for a valid claim token, or `nil`.
  """
  def get_managed_user_by_claim_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "claim"),
         %User{} = user <- Repo.one(query),
         true <- managed_unclaimed?(user) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for a client claiming a managed account.
  """
  def change_user_claim(%User{} = user, attrs \\ %{}) do
    User.claim_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Claims a managed account with the given token: sets the client's real email and
  password, clears the managed flag, and revokes the claim token. All of the
  account's existing data (assignment, calendar, meal plans) is preserved because
  it is the same user row.
  """
  def claim_managed_account(token, attrs) do
    case get_managed_user_by_claim_token(token) do
      nil ->
        :error

      user ->
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.update(:user, User.claim_changeset(user, attrs))
          |> Ecto.Multi.delete_all(
            :tokens,
            UserToken.user_and_contexts_query(user, ["claim", "confirm"])
          )
          |> Repo.transaction()

        case result do
          {:ok, %{user: user}} -> {:ok, user}
          {:error, :user, changeset, _} -> {:error, changeset}
        end
    end
  end

  @doc """
  Claims a managed account with the given token using a third-party identity.

  `oauth_attrs` is the provider profile (`:email`, `:name`, `:profile_pic`). The
  account keeps its data and becomes an ordinary confirmed OAuth account with no
  password. Returns `{:error, :email_taken}` if the provider email already
  belongs to another account.
  """
  def claim_managed_account_with_oauth(token, oauth_attrs) do
    case get_managed_user_by_claim_token(token) do
      nil ->
        :error

      user ->
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.update(:user, User.claim_oauth_changeset(user, oauth_attrs))
          |> Ecto.Multi.delete_all(
            :tokens,
            UserToken.user_and_contexts_query(user, ["claim", "confirm"])
          )
          |> Repo.transaction()

        case result do
          {:ok, %{user: user}} -> {:ok, user}
          {:error, :user, _changeset, _} -> {:error, :email_taken}
        end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.
  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  @doc """
  Delivers the update email instructions to the given user.
  """
  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.
  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc """
  Delivers the confirmation email instructions to the given user.
  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.
  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
