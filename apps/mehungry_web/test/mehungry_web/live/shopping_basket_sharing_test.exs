defmodule MehungryWeb.ShoppingBasketSharingTest do
  @moduledoc """
  The shared-shopping-list flows on `/basket`: inviting, the invitation link
  page, a member's view of someone else's list, and live updates between two
  sessions. See `docs/features/shared_basket.md`.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Inventory

  # A confirmed user plus a conn logged in as them.
  defp session(conn) do
    user = AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)
    {conn, Accounts.get_user!(user.id)}
  end

  defp token_from(url), do: url |> String.split("/") |> List.last()

  setup %{conn: conn} do
    {owner_conn, owner} = session(conn)
    {friend_conn, friend} = session(build_conn())

    {:ok, basket} =
      Inventory.create_shopping_basket(%{user_id: owner.id, title: "Weekly groceries"})

    {:ok, _} =
      Inventory.add_item(basket.id, %{name: "Tomatoes", quantity: 4.0, added_by_id: owner.id})

    %{
      owner_conn: owner_conn,
      owner: owner,
      friend_conn: friend_conn,
      friend: friend,
      basket: basket
    }
  end

  defp share!(owner, basket, member) do
    {:ok, _invitation, token} = Inventory.invite_to_basket(owner, basket.id)
    {:ok, _} = Inventory.accept_invitation_by_token(member, token)
    :ok
  end

  describe "inviting" do
    test "the owner creates a link from the Share modal", %{owner_conn: conn, basket: basket} do
      {:ok, view, _html} = live(conn, ~p"/basket")

      html = view |> element("#share-basket-button") |> render_click()
      assert html =~ "People on this list"

      html = view |> form("#invite-form", %{"email" => ""}) |> render_submit()
      assert html =~ "/basket/invitations/"
      assert html =~ "Waiting for an answer"
      assert [_] = Inventory.list_pending_basket_invitations(basket.id)
    end

    test "inviting by email sends the link and can be revoked", %{
      owner_conn: conn,
      basket: basket
    } do
      {:ok, view, _html} = live(conn, ~p"/basket")
      view |> element("#share-basket-button") |> render_click()

      html = view |> form("#invite-form", %{"email" => "partner@example.com"}) |> render_submit()
      assert html =~ "partner@example.com"

      assert_email_sent(fn email ->
        assert email.to == [{"", "partner@example.com"}]
        assert email.text_body =~ "/basket/invitations/"
        assert email.text_body =~ "Weekly groceries"
      end)

      [invitation] = Inventory.list_pending_basket_invitations(basket.id)
      html = render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})
      refute html =~ "partner@example.com"
      assert Inventory.list_pending_basket_invitations(basket.id) == []
    end

    test "a registered invitee sees the invitation on /basket and can join", %{
      owner: owner,
      friend_conn: conn,
      friend: friend,
      basket: basket
    } do
      {:ok, _, _} = Inventory.invite_to_basket(owner, basket.id, %{email: friend.email})

      {:ok, view, html} = live(conn, ~p"/basket")
      assert html =~ "invited you to share"
      # The contents stay hidden until they accept.
      refute html =~ "Tomatoes"

      [invitation] = Inventory.list_basket_invitations_for_user(friend.id)
      html = render_click(view, "accept_invitation", %{"id" => to_string(invitation.id)})

      assert html =~ "Tomatoes"
      refute html =~ "invited you to share"
      assert Inventory.basket_role(basket.id, friend.id) == :member
    end
  end

  describe "the invitation link" do
    test "shows who and which list, then joins", %{
      owner: owner,
      friend_conn: conn,
      basket: basket
    } do
      {:ok, _, url} = MehungryWeb.BasketSharing.invite(owner, basket.id, "")

      {:ok, view, html} = live(conn, ~p"/basket/invitations/#{token_from(url)}")
      assert html =~ "Weekly groceries"
      refute html =~ "Tomatoes"

      view |> element("#accept-invitation") |> render_click()
      assert_redirect(view, ~p"/basket?basket_id=#{basket.id}")
    end

    test "an unknown or used link says so", %{friend_conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/basket/invitations/not-a-real-token")
      assert html =~ "no longer valid"
    end

    test "a signed-out visitor is sent to log in first", %{owner: owner, basket: basket} do
      {:ok, _, url} = MehungryWeb.BasketSharing.invite(owner, basket.id, "")

      assert {:error, {:redirect, %{to: to}}} =
               live(build_conn(), ~p"/basket/invitations/#{token_from(url)}")

      assert to =~ "login"
    end
  end

  describe "a member" do
    setup %{owner: owner, basket: basket, friend: friend} do
      share!(owner, basket, friend)
    end

    test "sees the shared list, marked as shared, without owner controls", %{
      friend_conn: conn,
      basket: basket
    } do
      {:ok, view, html} = live(conn, ~p"/basket?basket_id=#{basket.id}")

      assert html =~ "Tomatoes"
      assert html =~ "Shared"

      refute has_element?(
               view,
               ~s|button[phx-click="delete_basket"][phx-value-id="#{basket.id}"]|
             )

      refute has_element?(view, ~s|button[phx-click="edit_basket"][phx-value-id="#{basket.id}"]|)
      assert has_element?(view, ~s|button[phx-click="leave_basket"][phx-value-id="#{basket.id}"]|)
    end

    test "can add and tick off items, with attribution", %{
      friend_conn: conn,
      friend: friend,
      basket: basket
    } do
      {:ok, view, _html} = live(conn, ~p"/basket?basket_id=#{basket.id}")
      [item] = Inventory.get_shopping_basket!(basket.id).basket_items

      html = render_click(view, "toggle_basket", %{"id" => to_string(item.id), "type" => "item"})
      assert html =~ "bought by you"

      ticked = Inventory.get_basket_item!(item.id)
      assert ticked.in_storage
      assert ticked.acquired_by_id == friend.id
    end

    test "cannot rename, delete or share the owner's list", %{
      friend_conn: conn,
      basket: basket
    } do
      {:ok, view, _html} = live(conn, ~p"/basket?basket_id=#{basket.id}")

      render_click(view, "delete_basket", %{"id" => to_string(basket.id)})
      assert Inventory.get_shopping_basket!(basket.id)

      view |> element("#share-basket-button") |> render_click()
      refute has_element?(view, "#invite-form")

      html = render_submit(view, "send_invite", %{"email" => ""})
      refute html =~ "/basket/invitations/"
      assert Inventory.list_pending_basket_invitations(basket.id) == []
    end

    test "can leave", %{friend_conn: conn, friend: friend, basket: basket} do
      {:ok, view, _html} = live(conn, ~p"/basket?basket_id=#{basket.id}")

      html = render_click(view, "leave_basket", %{"id" => to_string(basket.id)})
      refute html =~ "Tomatoes"
      assert Inventory.basket_role(basket.id, friend.id) == nil
    end
  end

  describe "live updates" do
    setup %{owner: owner, basket: basket, friend: friend} do
      share!(owner, basket, friend)
    end

    test "an item one person adds appears for the other", %{
      owner_conn: owner_conn,
      friend_conn: friend_conn,
      friend: friend,
      basket: basket
    } do
      {:ok, owner_view, _} = live(owner_conn, ~p"/basket?basket_id=#{basket.id}")
      {:ok, _friend_view, _} = live(friend_conn, ~p"/basket?basket_id=#{basket.id}")

      {:ok, _} =
        Inventory.add_item(basket.id, %{name: "Feta", quantity: 1.0, added_by_id: friend.id})

      assert render(owner_view) =~ "Feta"
    end

    test "ticking, editing and deleting a line show up for the other", %{
      owner_conn: owner_conn,
      friend_conn: friend_conn,
      basket: basket
    } do
      {:ok, owner_view, _} = live(owner_conn, ~p"/basket?basket_id=#{basket.id}")
      {:ok, friend_view, _} = live(friend_conn, ~p"/basket?basket_id=#{basket.id}")
      [item] = Inventory.get_shopping_basket!(basket.id).basket_items
      params = %{"id" => to_string(item.id), "type" => "item"}

      refute render(owner_view) =~ "line-through"

      # The friend's own view updates from the result, the owner's from the event.
      assert render_click(friend_view, "toggle_basket", params) =~ "line-through"
      assert render(owner_view) =~ "line-through"

      render_click(friend_view, "edit_item", params)

      render_submit(friend_view, "update_item", %{
        "item_id" => to_string(item.id),
        "item_type" => "item",
        "name" => "Cherry tomatoes",
        "quantity" => "6"
      })

      assert render(friend_view) =~ "Cherry tomatoes"
      assert render(owner_view) =~ "Cherry tomatoes"

      refute render_click(friend_view, "delete_item", params) =~ "Cherry tomatoes"
      refute render(owner_view) =~ "Cherry tomatoes"
    end

    test "a removed member is moved off the list", %{
      owner: owner,
      friend_conn: friend_conn,
      friend: friend,
      basket: basket
    } do
      {:ok, friend_view, html} = live(friend_conn, ~p"/basket?basket_id=#{basket.id}")
      assert html =~ "Tomatoes"

      :ok = Inventory.remove_basket_member(owner, basket.id, friend.id)

      html = render(friend_view)
      refute html =~ "Tomatoes"
      assert html =~ "no longer available"
    end
  end

  test "a stranger still cannot open the list", %{basket: basket} do
    {conn, _stranger} = session(build_conn())

    {:ok, view, html} = live(conn, ~p"/basket?basket_id=#{basket.id}")
    refute html =~ "Tomatoes"

    html = render_click(view, "select_shopping_basket", %{"id" => to_string(basket.id)})
    refute html =~ "Tomatoes"
  end
end
