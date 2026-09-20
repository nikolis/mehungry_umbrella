defmodule MehungryWeb.UserClaimController do
  @moduledoc """
  Lets a new registrant claim a login-less account a professional created for
  them. The claim token proves possession of the shareable link; on success the
  account gains real credentials and keeps all of its existing data.
  """
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias MehungryWeb.UserAuth

  def edit(conn, %{"token" => token}) do
    case Accounts.get_managed_user_by_claim_token(token) do
      nil ->
        conn
        |> put_flash(:error, "This claim link is invalid or has expired.")
        |> redirect(to: Routes.user_registration_path(conn, :new))

      user ->
        # Render an empty email field — the placeholder address on the managed
        # account is synthetic and must not be shown or submitted.
        changeset = Accounts.change_user_claim(%{user | email: nil})

        render(conn, "edit.html",
          changeset: changeset,
          token: token,
          managed_name: user.name,
          page_title: "Claim Your Account"
        )
    end
  end

  @doc """
  Stashes the claim token in the session and kicks off the provider OAuth flow,
  so the callback can claim this managed account instead of creating a new user.
  """
  def oauth_request(conn, %{"token" => token, "provider" => provider})
      when provider in ["google", "facebook"] do
    case Accounts.get_managed_user_by_claim_token(token) do
      nil ->
        conn
        |> put_flash(:error, "This claim link is invalid or has expired.")
        |> redirect(to: Routes.user_registration_path(conn, :new))

      _user ->
        conn
        |> put_session("claim_token", token)
        |> redirect(to: Routes.auth_path(conn, :request, provider))
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.claim_managed_account(token, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome! Your account is ready.")
        |> UserAuth.log_in_user(user, user_params)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html",
          changeset: changeset,
          token: token,
          managed_name: Ecto.Changeset.get_field(changeset, :name),
          page_title: "Claim Your Account"
        )

      :error ->
        conn
        |> put_flash(:error, "This claim link is invalid or has expired.")
        |> redirect(to: Routes.user_registration_path(conn, :new))
    end
  end
end
