defmodule Mehungry.Accounts.TestAccounts do
  @moduledoc """
  Deterministic, pre-confirmed accounts for exercising third-party / bot
  integrations (OAuth callbacks, social publishing, API clients) against a
  known set of users.

  This is a *testing* affordance: the three accounts have fixed emails and a
  fixed password, are created already `confirmed_at` (bypassing the email
  confirmation flow), and can be wiped back to a clean slate via `reset/0`.

  Reachable two ways:

    * `mix test_accounts.seed` / `mix test_accounts.reset` (the script)
    * the token/env-gated `/test-accounts/*` routes (the URL)

  Never enabled in production without an explicit `TEST_ACCOUNTS_TOKEN`
  (see `MehungryWeb.TestAccountsController`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{Admin, Auth, User}

  # Fixed, checked-in credentials. Domain `.test` is reserved (RFC 2606) so
  # these can never collide with a real deliverable inbox.
  @password "TestBot-Passw0rd"

  @accounts [
    %{email: "bot1@mehungry.test", name: "Test Bot One"},
    %{email: "bot2@mehungry.test", name: "Test Bot Two"},
    %{email: "bot3@mehungry.test", name: "Test Bot Three"}
  ]

  @doc "The shared password for every test account."
  def password, do: @password

  @doc "The static definitions (email + name) of the three test accounts."
  def definitions, do: @accounts

  @doc """
  Ensures all three accounts exist and are confirmed. Idempotent: existing
  accounts are left in place (and re-confirmed if needed), missing ones are
  created. Returns the list of `%User{}`.
  """
  def seed do
    Enum.map(@accounts, &ensure_account/1)
  end

  @doc """
  Deletes any of the three accounts that exist (full cascade via
  `Accounts.Admin.delete_user/1`) and recreates them fresh. Returns the list of
  newly created `%User{}`.
  """
  def reset do
    Enum.each(@accounts, &delete_if_present/1)
    seed()
  end

  @doc """
  A summary of the current state of the three accounts, suitable for a JSON or
  console response.
  """
  def status do
    Enum.map(@accounts, fn %{email: email} = acc ->
      case Admin.get_user_by_email(email) do
        %User{} = user ->
          %{
            email: email,
            name: acc.name,
            password: @password,
            exists: true,
            confirmed: not is_nil(user.confirmed_at),
            id: user.id
          }

        _ ->
          %{email: email, name: acc.name, password: @password, exists: false, confirmed: false}
      end
    end)
  end

  defp ensure_account(%{email: email, name: name}) do
    case Admin.get_user_by_email(email) do
      %User{} = user -> confirm_and_name(user, name)
      _ -> create_confirmed(email, name)
    end
  end

  defp create_confirmed(email, name) do
    {:ok, user} = Auth.register_user(%{email: email, password: @password})
    confirm_and_name(user, name)
  end

  defp confirm_and_name(user, name) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> Ecto.Changeset.change(confirmed_at: user.confirmed_at || now, name: name)
    |> Repo.update!()
  end

  defp delete_if_present(%{email: email}) do
    case Admin.get_user_by_email(email) do
      %User{} = user -> Admin.delete_user(user)
      _ -> :ok
    end
  end
end
