defmodule MehungryWeb.BasketSharing do
  @moduledoc """
  Web-side half of inviting someone to a shared shopping list: the core
  (`Mehungry.Inventory.Sharing.invite/3`) creates the invitation and returns the
  one-time token; this builds the link and, when the invitation was addressed to
  an email, sends it. Shared by the `/basket` LiveView and the `/api/v1` sharing
  controller so both clients invite identically. See
  `docs/features/shared_basket.md`.
  """
  use Gettext, backend: MehungryWeb.Gettext

  alias Mehungry.Accounts.UserNotifier
  alias Mehungry.Inventory
  alias Mehungry.Inventory.Sharing

  @doc """
  Invites to `basket_id` as `inviter`. `email` may be blank (link-only).
  Returns `{:ok, invitation, url}` or the core's `{:error, reason}`.
  """
  def invite(inviter, basket_id, email, locale \\ "en") do
    with {:ok, invitation, token} <-
           Inventory.invite_to_basket(inviter, basket_id, %{email: email}) do
      url = invitation_url(token)
      maybe_email(invitation, inviter, email, url, locale)
      {:ok, invitation, url}
    end
  end

  @doc "The public link for an invitation token."
  def invitation_url(token), do: MehungryWeb.Endpoint.url() <> "/basket/invitations/" <> token

  # Sent to the address as typed (the stored one is canonicalized). Skipped for
  # link-only invitations and for a blocked pair.
  defp maybe_email(invitation, inviter, email, url, locale) do
    if Sharing.email_deliverable?(invitation) do
      basket = Inventory.get_shopping_basket!(invitation.shopping_basket_id)

      UserNotifier.deliver_basket_invitation(
        String.trim(email),
        Sharing.display_name(inviter) || gettext("A Mehungry user"),
        basket.title,
        url,
        locale
      )
    end

    :ok
  end

  @doc "A user-facing message for an invitation error reason."
  def error_message(:email_not_confirmed),
    do: gettext("Confirm your email address before inviting people.")

  def error_message(:rate_limited),
    do: gettext("You've sent a lot of invitations. Please try again later.")

  def error_message(:basket_full),
    do: gettext("This list already has the maximum number of people.")

  def error_message(:too_many_pending),
    do: gettext("Too many unanswered invitations. Revoke one before sending more.")

  def error_message(:invalid_email), do: gettext("That doesn't look like an email address.")
  def error_message(:cannot_invite_yourself), do: gettext("You're already on this list.")
  def error_message(:already_member), do: gettext("That person is already on this list.")
  def error_message(:invalid), do: gettext("This invitation is no longer valid.")
  def error_message(_), do: gettext("Could not complete that. Please try again.")
end
