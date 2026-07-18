defmodule Mehungry.Accounts.OAuth do
  @moduledoc """
  Third-party (Ueberauth) authentication: find-or-create from provider auth
  payloads, profile-pic sync, auto-confirmation, and provider token storage
  (DB tokens plus the per-user token cache).
  """

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Accounts.{Admin, Profiles, User}
  alias Ueberauth.Auth

  # Token-cache entries predate this module and are keyed under
  # `Mehungry.Accounts`; keep that namespace so existing entries stay valid.
  @cache_key_ns Mehungry.Accounts

  def get_user_tokens(user, domain) do
    case Cachex.get(:cache_user_tokens, {@cache_key_ns, user.id}) do
      {:ok, nil} ->
        nil

      {:ok, user_tokens} ->
        Map.get(user_tokens, domain, nil)
    end
  end

  def put_user_token(user, token, domain) do
    user_tokens =
      case Cachex.get(:cache_user_tokens, {@cache_key_ns, user.id}) do
        {:ok, nil} ->
          %{}
          |> Map.put(domain, token)

        {:ok, %{} = existing_user_tokens} ->
          existing_user_tokens
          |> Map.put(domain, token)
      end

    Cachex.put(:cache_user_tokens, {@cache_key_ns, user.id}, user_tokens)
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.registration_3rd_party_changeset(attrs)
    |> Repo.update()
  end

  def update_user_tokens(%User{} = user, attrs) do
    user
    |> User.tokens_changeset(attrs)
    |> Repo.update()
  end

  def register_3rd_party_user(attrs) do
    result =
      %User{}
      |> User.registration_3rd_party_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        Profiles.create_user_profile_if_needed(user)
        {:ok, user}

      _ ->
        result
    end
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
    email = email_from_auth(auth) || fallback_email_from_auth(auth)

    user = if is_binary(email), do: Admin.get_user_by_canonical_email(email), else: nil

    if user do
      user =
        auth
        |> verify_3rd_party_user_changes(user)
        |> maybe_confirm_user()

      {:ok, user}
    else
      register_3rd_party_user(basic_info(auth))
    end
  end

  @doc """
  Confirms a user's email if it is not already confirmed.

  Google/Facebook have already verified the address, so an existing account that
  never confirmed (a password signup that never clicked the email link, or a
  legacy account missing `confirmed_at`) should be treated as confirmed the
  moment they authenticate via OAuth. New OAuth signups are confirmed by
  `registration_3rd_party_changeset`, so this only matters for pre-existing
  accounts. Returns the (possibly updated) user.
  """
  def maybe_confirm_user(%User{confirmed_at: nil} = user) do
    case user |> User.confirm_changeset() |> Repo.update() do
      {:ok, confirmed_user} ->
        confirmed_user

      {:error, error} ->
        Logger.error("Failed to auto-confirm OAuth user #{user.id}: #{inspect(error)}")
        user
    end
  end

  def maybe_confirm_user(%User{} = user), do: user

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

  defp fallback_email_from_auth(%{provider: :facebook, uid: uid}), do: "#{uid}@facebook.user"
  defp fallback_email_from_auth(_), do: nil

  defp basic_info(auth) do
    email = email_from_auth(auth)

    case auth.strategy do
      Ueberauth.Strategy.Facebook ->
        %{
          name: name_from_auth(auth),
          email: email || fallback_email_from_auth(auth),
          profile_pic: avatar_from_auth(auth),
          provider: "facebook"
        }

      Ueberauth.Strategy.Google ->
        %{
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
end
