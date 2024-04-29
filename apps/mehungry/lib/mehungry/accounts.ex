defmodule Mehungry.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo
  alias Ueberauth.Auth
  require Logger

  alias Mehungry.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def register_3rd_party_user(attrs) do
    %User{}
    |> User.registration_3rd_party_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.registration_3rd_party_changeset(attrs)
    |> Repo.update()
  end

  def verify_3rd_party_user_changes(
        %Auth{strategy: Ueberauth.Strategy.Facebook} = auth,
        %User{} = user
      ) do
    case user.profile_pic == auth.extra.raw_info.user["picture"]["data"]["url"] do
      true ->
        user

      false ->
        case update_user(user, %{profile_pic: auth.extra.raw_info.user["picture"]["data"]["url"]}) do
          {:ok, user} ->
            user

          {:error, error} ->
            Logger.error("Problem getting info from 3rd party authentication: #{inspect(error)}")
            user
        end
    end
  end

  def verify_3rd_party_user_changes(%Auth{} = auth, %User{} = user) do
    case user.profile_pic == auth.info.image do
      true ->
        user

      false ->
        case update_user(user, %{profile_pic: auth.info.image}) do
          {:ok, user} ->
            user

          {:error, error} ->
            Logger.error("Problem getting info from 3rd party authentication: #{inspect(error)}")
            user
        end
    end
  end

  def find_or_create(%Auth{} = auth) do
    user =
      email_from_auth(auth)
      |> get_user_by_email()

    if user do
      verify_3rd_party_user_changes(auth, user)
      {:ok, user}
    else
      register_3rd_party_user(basic_info(auth))
    end
  end

  # github does it this way
  defp avatar_from_auth(%{info: %{urls: %{avatar_url: image}}}), do: image

  # Google Does it this way
  defp avatar_from_auth(%{info: %{image: image}}) do
    image
  end

  # facebook does it this way
  defp avatar_from_auth(%{extra: %{raw_info: %{user: user}}} = _extra) do
    user["picture"]["data"]["url"]
  end

  defp email_from_auth(%{info: %{email: email}}), do: email

  # default case if nothing matches
  # defp avatar_from_auth(auth) do
  # Logger.warn("#{auth.provider} needs to find an avatar URL!")
  # Logger.debug(Jason.encode!(auth))
  # nil
  # end

  defp basic_info(auth) do
    email = email_from_auth(auth)

    case auth.strategy do
      Ueberauth.Strategy.Facebook ->
        %{
          # uid: auth.uid,
          name: name_from_auth(auth),
          email: email,
          profile_pic: avatar_from_auth(auth),
          provider: "facebook"
        }

      Ueberauth.Strategy.Google ->
        %{
          # uid: auth.uid,
          name: name_from_auth(auth),
          email: email,
          profile_pic: avatar_from_auth(auth),
          provider: "google"
        }
    end
  end

  defp name_from_auth(auth) do
    if auth.info.name do
      auth.info.name
    else
      name =
        [auth.info.first_name, auth.info.last_name]
        |> Enum.filter(&(&1 != nil and &1 != ""))

      if Enum.empty?(name) do
        auth.info.nickname
      else
        Enum.join(name, " ")
      end
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

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

  ## Examples

      iex> deliver_update_email_instructions(user, current_email, &Routes.user_update_email_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

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

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &Routes.user_confirmation_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &Routes.user_confirmation_url(conn, :edit, &1))
      {:error, :already_confirmed}

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

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &Routes.user_reset_password_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

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

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

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

  alias Mehungry.Accounts.UserCategoryRule

  @doc """
  Returns the list of user_category_rules.

  ## Examples

      iex> list_user_category_rules()
      [%UserCategoryRule{}, ...]

  """
  def list_user_category_rules do
    Repo.all(UserCategoryRule)
  end

  @doc """
  Gets a single user_category_rule.

  Raises `Ecto.NoResultsError` if the User category rule does not exist.

  ## Examples

      iex> get_user_category_rule!(123)
      %UserCategoryRule{}

      iex> get_user_category_rule!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_category_rule!(id), do: Repo.get!(UserCategoryRule, id)

  @doc """
  Creates a user_category_rule.

  ## Examples

      iex> create_user_category_rule(%{field: value})
      {:ok, %UserCategoryRule{}}

      iex> create_user_category_rule(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_category_rule(attrs \\ %{}) do
    %UserCategoryRule{}
    |> UserCategoryRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_category_rule.

  ## Examples

      iex> update_user_category_rule(user_category_rule, %{field: new_value})
      {:ok, %UserCategoryRule{}}

      iex> update_user_category_rule(user_category_rule, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs) do
    user_category_rule
    |> UserCategoryRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_category_rule.

  ## Examples

      iex> delete_user_category_rule(user_category_rule)
      {:ok, %UserCategoryRule{}}

      iex> delete_user_category_rule(user_category_rule)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_category_rule(%UserCategoryRule{} = user_category_rule) do
    Repo.delete(user_category_rule)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_category_rule changes.

  ## Examples

      iex> change_user_category_rule(user_category_rule)
      %Ecto.Changeset{data: %UserCategoryRule{}}

  """
  def change_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs \\ %{}) do
    UserCategoryRule.changeset(user_category_rule, attrs)
  end

  alias Mehungry.Accounts.UserIngredientRule

  @doc """
  Returns the list of user_ingredient_rules.

  ## Examples

      iex> list_user_ingredient_rules()
      [%UserIngredientRule{}, ...]

  """
  def list_user_ingredient_rules do
    Repo.all(UserIngredientRule)
  end

  @doc """
  Gets a single user_ingredient_rule.

  Raises `Ecto.NoResultsError` if the User ingredient rule does not exist.

  ## Examples

      iex> get_user_ingredient_rule!(123)
      %UserIngredientRule{}

      iex> get_user_ingredient_rule!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_ingredient_rule!(id), do: Repo.get!(UserIngredientRule, id)

  @doc """
  Creates a user_ingredient_rule.

  ## Examples

      iex> create_user_ingredient_rule(%{field: value})
      {:ok, %UserIngredientRule{}}

      iex> create_user_ingredient_rule(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_ingredient_rule(attrs \\ %{}) do
    %UserIngredientRule{}
    |> UserIngredientRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_ingredient_rule.

  ## Examples

      iex> update_user_ingredient_rule(user_ingredient_rule, %{field: new_value})
      {:ok, %UserIngredientRule{}}

      iex> update_user_ingredient_rule(user_ingredient_rule, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs) do
    user_ingredient_rule
    |> UserIngredientRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_ingredient_rule.

  ## Examples

      iex> delete_user_ingredient_rule(user_ingredient_rule)
      {:ok, %UserIngredientRule{}}

      iex> delete_user_ingredient_rule(user_ingredient_rule)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule) do
    Repo.delete(user_ingredient_rule)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_ingredient_rule changes.

  ## Examples

      iex> change_user_ingredient_rule(user_ingredient_rule)
      %Ecto.Changeset{data: %UserIngredientRule{}}

  """
  def change_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs \\ %{}) do
    UserIngredientRule.changeset(user_ingredient_rule, attrs)
  end

  alias Mehungry.Accounts.UserProfile

  @doc """
  Returns the list of user_profiles.

  ## Examples

      iex> list_user_profiles()
      [%UserProfile{}, ...]

  """
  def list_user_profiles do
    Repo.all(UserProfile)
  end

  @doc """
  Gets a single user_profile.

  Raises `Ecto.NoResultsError` if the User profile does not exist.

  ## Examples

      iex> get_user_profile!(123)
      %UserProfile{}

      iex> get_user_profile!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_profile!(id), do: Repo.get!(UserProfile, id)

  def get_user_profile_by_user_id(id) do
    from(p in UserProfile,
      where: p.user_id == ^id
    )
    |> Repo.one()
    |> Repo.preload([:user_category_rules, :user_ingredient_rules])
  end

  @doc """
  Creates a user_profile.

  ## Examples

      iex> create_user_profile(%{field: value})
      {:ok, %UserProfile{}}

      iex> create_user_profile(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_profile(attrs \\ %{}) do
    %UserProfile{}
    |> UserProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_profile.

  ## Examples

      iex> update_user_profile(user_profile, %{field: new_value})
      {:ok, %UserProfile{}}

      iex> update_user_profile(user_profile, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_profile(%UserProfile{} = user_profile, attrs) do
    user_profile
    |> UserProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_profile.

  ## Examples

      iex> delete_user_profile(user_profile)
      {:ok, %UserProfile{}}

      iex> delete_user_profile(user_profile)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_profile(%UserProfile{} = user_profile) do
    Repo.delete(user_profile)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_profile changes.

  ## Examples

      iex> change_user_profile(user_profile)
      %Ecto.Changeset{data: %UserProfile{}}

  """
  def change_user_profile(%UserProfile{} = user_profile, attrs \\ %{}) do
    UserProfile.changeset(user_profile, attrs)
  end
end
