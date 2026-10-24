defmodule Mehungry.BetaSignups do
  @moduledoc """
  Context for the public Android beta-tester signup list (the `/trial` page).

  Stores interested emails and supports self-service removal both by email
  (on-page "remove me" box) and by a per-row token (one-click unsubscribe link
  embedded in emails).
  """
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Accounts.User
  alias Mehungry.BetaSignups.BetaSignup
  alias Mehungry.BetaSignups.BetaInviteSend

  def change_beta_signup(attrs \\ %{}) do
    BetaSignup.changeset(%BetaSignup{}, attrs)
  end

  def create_beta_signup(attrs) do
    %BetaSignup{}
    |> BetaSignup.changeset(attrs)
    |> Repo.insert()
  end

  def list_beta_signups do
    BetaSignup
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  def count do
    Repo.aggregate(BetaSignup, :count)
  end

  def get_beta_signup!(id), do: Repo.get!(BetaSignup, id)

  def get_by_token(token) when is_binary(token) do
    Repo.get_by(BetaSignup, unsubscribe_token: token)
  end

  def get_by_token(_), do: nil

  def delete_beta_signup(%BetaSignup{} = beta_signup), do: Repo.delete(beta_signup)

  @doc """
  Remove any signup whose canonical email matches `email`. Returns
  `{:ok, count}` with the number of rows deleted (0 when none matched).
  """
  def remove_by_email(email) when is_binary(email) do
    canonical = User.canonical_email(email)

    {count, _} =
      BetaSignup
      |> where([b], b.canonical_email == ^canonical)
      |> Repo.delete_all()

    {:ok, count}
  end

  def remove_by_email(_), do: {:ok, 0}

  @doc "Remove the signup for `token`. Returns the deleted email, or nil."
  def remove_by_token(token) do
    case get_by_token(token) do
      nil ->
        nil

      %BetaSignup{} = signup ->
        {:ok, _} = Repo.delete(signup)
        signup.email
    end
  end

  # ── Version send tracking ──────────────────────────────────────────────────

  @doc """
  Record that `version` was sent to `email`. Idempotent per (tester, version)
  — resending the same build keeps the original row. Links the matching
  `beta_signup` when the email is a registered tester.
  """
  def record_send(email, version, attrs \\ %{}) do
    canonical = User.canonical_email(email)
    signup = Repo.get_by(BetaSignup, canonical_email: canonical)

    base = %{
      "email" => email,
      "version" => version,
      "beta_signup_id" => signup && signup.id
    }

    %BetaInviteSend{}
    |> BetaInviteSend.changeset(Map.merge(base, Map.new(attrs, fn {k, v} -> {to_string(k), v} end)))
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:canonical_email, :version]
    )
  end

  @doc "All send rows, most recent first."
  def list_sends do
    BetaInviteSend
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> Repo.all()
  end

  @doc """
  Map of `canonical_email => [versions]` (most-recent first, de-duplicated) for
  every tester we've sent at least one build to.
  """
  def versions_by_tester do
    BetaInviteSend
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> Repo.all()
    |> Enum.group_by(& &1.canonical_email, & &1.version)
    |> Map.new(fn {canonical, versions} -> {canonical, Enum.uniq(versions)} end)
  end

  @doc """
  Registered signups that have NOT yet been sent `version`, most recent first.
  Pass `platform` (e.g. `"android"`) to restrict to testers interested in it.
  """
  def signups_missing_version(version, platform \\ nil) do
    sent =
      from(s in BetaInviteSend,
        where: s.version == ^version,
        select: s.canonical_email
      )

    query =
      from(b in BetaSignup,
        where: b.canonical_email not in subquery(sent),
        order_by: [desc: b.inserted_at]
      )

    query =
      if platform,
        do: from(b in query, where: fragment("? = ANY(?)", ^platform, b.platforms)),
        else: query

    Repo.all(query)
  end
end
