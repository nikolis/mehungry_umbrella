defmodule MehungryWeb.Api.V1.BasketSharingTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Accounts
  alias Mehungry.AccountsFixtures
  alias Mehungry.Inventory

  setup :register_and_log_in_api_user

  setup %{user: user} do
    {:ok, basket} =
      Inventory.create_shopping_basket(%{user_id: user.id, title: "Weekly groceries"})

    {:ok, item} =
      Inventory.add_item(basket.id, %{name: "Milk", quantity: 1.0, added_by_id: user.id})

    friend = AccountsFixtures.user_fixture()
    {:ok, %{user: friend}} = Mehungry.Repo.transaction(Accounts.confirm_user_multi(friend))

    %{
      basket: basket,
      item: item,
      friend: friend,
      friend_conn: put_api_token(build_conn(), friend)
    }
  end

  defp token_from(url), do: url |> String.split("/") |> List.last()

  defp invite!(conn, basket, body \\ %{}) do
    conn |> post(~p"/api/v1/baskets/#{basket.id}/invitations", body) |> json_response(201)
  end

  defp share!(conn, friend_conn, basket) do
    %{"data" => %{"url" => url}} = invite!(conn, basket)

    friend_conn
    |> post(~p"/api/v1/me/basket-invitations/accept", %{"token" => token_from(url)})
    |> json_response(200)
  end

  test "the owner invites by link and lists / revokes pending invitations", %{
    conn: conn,
    basket: basket
  } do
    assert %{"data" => %{"id" => id, "url" => url, "status" => "pending", "email" => nil}} =
             invite!(conn, basket)

    assert url =~ "/basket/invitations/"

    assert %{"data" => [%{"id" => ^id, "url" => nil}]} =
             conn |> get(~p"/api/v1/baskets/#{basket.id}/invitations") |> json_response(200)

    assert conn |> delete(~p"/api/v1/baskets/#{basket.id}/invitations/#{id}") |> response(204)

    assert %{"data" => []} =
             conn |> get(~p"/api/v1/baskets/#{basket.id}/invitations") |> json_response(200)
  end

  test "an addressed invitee lists, then accepts in-app", %{
    conn: conn,
    basket: basket,
    friend: friend,
    friend_conn: friend_conn
  } do
    invite!(conn, basket, %{"email" => friend.email})

    assert %{"data" => [%{"id" => id, "basket_title" => "Weekly groceries"} = incoming]} =
             friend_conn |> get(~p"/api/v1/me/basket-invitations") |> json_response(200)

    # Before accepting: no contents, and the list itself is a 404.
    refute Map.has_key?(incoming, "items")
    assert friend_conn |> get(~p"/api/v1/baskets/#{basket.id}") |> json_response(404)

    assert %{"data" => %{"role" => "member", "shared" => true, "items" => [%{"name" => "Milk"}]}} =
             friend_conn
             |> post(~p"/api/v1/me/basket-invitations/#{id}/accept")
             |> json_response(200)
  end

  test "an invitee can decline", %{
    conn: conn,
    basket: basket,
    friend: friend,
    friend_conn: friend_conn
  } do
    invite!(conn, basket, %{"email" => friend.email})

    %{"data" => [%{"id" => id}]} =
      friend_conn |> get(~p"/api/v1/me/basket-invitations") |> json_response(200)

    assert friend_conn |> post(~p"/api/v1/me/basket-invitations/#{id}/decline") |> response(204)

    assert friend_conn
           |> post(~p"/api/v1/me/basket-invitations/#{id}/accept")
           |> json_response(404)

    assert Inventory.basket_role(basket.id, friend.id) == nil
  end

  test "a member reads and edits the shared list; `/basket` stays their own", %{
    conn: conn,
    basket: basket,
    item: item,
    friend: friend,
    friend_conn: friend_conn
  } do
    share!(conn, friend_conn, basket)

    assert %{"data" => baskets} = friend_conn |> get(~p"/api/v1/baskets") |> json_response(200)
    assert [%{"role" => "member", "shared" => true, "people" => people}] = baskets
    assert [%{"role" => "owner"}, %{"role" => "member", "id" => friend_id}] = people
    assert friend_id == friend.id
    refute Enum.any?(people, &Map.has_key?(&1, "email"))

    # Tick off the owner's item.
    assert %{"data" => %{"in_storage" => true, "acquired_by_id" => ^friend_id}} =
             friend_conn
             |> put(~p"/api/v1/basket/items/#{item.id}", %{"in_storage" => true})
             |> json_response(200)

    # Add to the shared list by id.
    assert %{"data" => %{"name" => "Bread", "added_by_id" => ^friend_id}} =
             friend_conn
             |> post(~p"/api/v1/basket/items", %{"name" => "Bread", "basket_id" => basket.id})
             |> json_response(201)

    assert length(Inventory.get_shopping_basket!(basket.id).basket_items) == 2

    # The default basket is still the member's own, not the shared one.
    assert %{"data" => %{"id" => own_id, "role" => "owner"}} =
             friend_conn |> get(~p"/api/v1/basket") |> json_response(200)

    refute own_id == basket.id
  end

  test "a non-member is refused on every path", %{
    basket: basket,
    item: item,
    friend_conn: stranger_conn,
    friend: stranger
  } do
    assert stranger_conn |> get(~p"/api/v1/baskets/#{basket.id}") |> json_response(404)

    assert stranger_conn
           |> get(~p"/api/v1/baskets/#{basket.id}/invitations")
           |> json_response(404)

    assert stranger_conn
           |> post(~p"/api/v1/baskets/#{basket.id}/invitations", %{})
           |> json_response(404)

    assert stranger_conn
           |> post(~p"/api/v1/basket/items", %{"name" => "X", "basket_id" => basket.id})
           |> json_response(404)

    assert stranger_conn
           |> put(~p"/api/v1/basket/items/#{item.id}", %{"in_storage" => true})
           |> json_response(404)

    assert stranger_conn |> delete(~p"/api/v1/basket/items/#{item.id}") |> json_response(404)

    assert stranger_conn
           |> delete(~p"/api/v1/baskets/#{basket.id}/members/#{stranger.id}")
           |> json_response(404)

    assert %{"data" => []} = stranger_conn |> get(~p"/api/v1/baskets") |> json_response(200)
  end

  test "a member cannot invite or remove others, but can leave", %{
    conn: conn,
    user: owner,
    basket: basket,
    friend: friend,
    friend_conn: friend_conn
  } do
    share!(conn, friend_conn, basket)

    assert friend_conn
           |> post(~p"/api/v1/baskets/#{basket.id}/invitations", %{})
           |> json_response(404)

    assert friend_conn
           |> delete(~p"/api/v1/baskets/#{basket.id}/members/#{owner.id}")
           |> json_response(403)

    assert friend_conn
           |> delete(~p"/api/v1/baskets/#{basket.id}/members/#{friend.id}")
           |> response(204)

    assert friend_conn |> get(~p"/api/v1/baskets/#{basket.id}") |> json_response(404)
  end

  test "the owner removes a member", %{
    conn: conn,
    basket: basket,
    friend: friend,
    friend_conn: friend_conn
  } do
    share!(conn, friend_conn, basket)

    assert conn |> delete(~p"/api/v1/baskets/#{basket.id}/members/#{friend.id}") |> response(204)
    assert Inventory.basket_role(basket.id, friend.id) == nil
  end

  test "invitation errors are 422 with a code", %{conn: conn, basket: basket, user: owner} do
    assert %{"errors" => %{"code" => "cannot_invite_yourself"}} =
             conn
             |> post(~p"/api/v1/baskets/#{basket.id}/invitations", %{"email" => owner.email})
             |> json_response(422)

    assert %{"errors" => %{"code" => "invalid_email"}} =
             conn
             |> post(~p"/api/v1/baskets/#{basket.id}/invitations", %{"email" => "nope"})
             |> json_response(422)
  end

  test "a bad or reused token is a 404", %{conn: conn, basket: basket, friend_conn: friend_conn} do
    assert friend_conn
           |> post(~p"/api/v1/me/basket-invitations/accept", %{"token" => "garbage"})
           |> json_response(404)

    %{"data" => %{"url" => url}} = invite!(conn, basket)
    share_body = %{"token" => token_from(url)}

    assert friend_conn
           |> post(~p"/api/v1/me/basket-invitations/accept", share_body)
           |> json_response(200)

    other = AccountsFixtures.user_fixture()
    {:ok, %{user: other}} = Mehungry.Repo.transaction(Accounts.confirm_user_multi(other))

    assert build_conn()
           |> put_api_token(other)
           |> post(~p"/api/v1/me/basket-invitations/accept", share_body)
           |> json_response(404)
  end
end
