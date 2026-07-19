defmodule Mehungry.InstagramTest do
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures

  alias Mehungry.Accounts
  alias Mehungry.Social.Instagram
  alias Mehungry.Social.Instagram.Token

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :instagram_stub) end)
    %{user: user_fixture()}
  end

  defp stub(overrides), do: Application.put_env(:mehungry, :instagram_stub, overrides)

  defp set_token(user, token) do
    {:ok, user} = Accounts.update_user_tokens(user, %{"instagram_token" => token})
    user
  end

  defp reload_token(user), do: Accounts.get_user!(user.id).instagram_token

  defp connected_token(attrs \\ %{}) do
    Map.merge(
      Token.build(
        %{"access_token" => "existing", "token_type" => "bearer", "expires_in" => 5_184_000},
        "42"
      ),
      attrs
    )
  end

  describe "connect_account/3" do
    test "stores the long-lived token in the new shape", %{user: user} do
      assert {:ok, updated} = Instagram.connect_account(user, "short", 123)

      token = updated.instagram_token
      assert token["access_token"] == "stub-long-lived"
      assert token["user_id"] == "123"
      assert token["status"] == "active"
      assert token["expires_at"]
      assert Token.status(token) == :connected
    end

    test "saves nothing when the exchange fails", %{user: user} do
      stub(
        exchange_long_lived_token: fn _short ->
          {:error, {:http_error, 400, %{"error_type" => "OAuthException"}}}
        end
      )

      assert {:error, {:http_error, 400, _}} = Instagram.connect_account(user, "short", 123)
      assert reload_token(user) == %{}
    end
  end

  describe "refresh_user_token/1" do
    test "updates the token and preserves obtained_at", %{user: user} do
      user = set_token(user, connected_token(%{"obtained_at" => "2026-01-01T00:00:00Z"}))

      assert {:ok, updated} = Instagram.refresh_user_token(user)
      assert updated.instagram_token["access_token"] == "stub-refreshed"
      assert updated.instagram_token["obtained_at"] == "2026-01-01T00:00:00Z"
      assert updated.instagram_token["user_id"] == "42"
    end

    test "marks the token stale on an invalid-token 4xx", %{user: user} do
      user = set_token(user, connected_token())

      stub(
        refresh_long_lived_token: fn _token ->
          {:error,
           {:http_error, 400,
            %{"error" => %{"type" => "OAuthException", "code" => 190, "message" => "Session expired"}}}}
        end
      )

      assert {:error, {:http_error, 400, _}} = Instagram.refresh_user_token(user)
      assert Token.status(reload_token(user)) == :stale
    end

    test "leaves the token untouched on other 4xx errors", %{user: user} do
      user = set_token(user, connected_token())

      stub(
        refresh_long_lived_token: fn _token ->
          {:error, {:http_error, 400, %{"error" => %{"message" => "Try again later"}}}}
        end
      )

      assert {:error, _} = Instagram.refresh_user_token(user)
      assert reload_token(user)["access_token"] == "existing"
      assert Token.status(reload_token(user)) in [:connected, :expiring]
    end

    test "leaves the token untouched on transport errors", %{user: user} do
      user = set_token(user, connected_token())
      stub(refresh_long_lived_token: fn _token -> {:error, {:transport_error, :timeout}} end)

      assert {:error, {:transport_error, :timeout}} = Instagram.refresh_user_token(user)
      assert reload_token(user)["access_token"] == "existing"
    end
  end

  describe "post_recipe/2" do
    defp recipe do
      %{
        title: "T",
        description: "D",
        image_url: "https://example.com/img.jpg",
        recipe_ingredients: [],
        steps: [],
        nutrients: %{}
      }
    end

    test "errors when not connected", %{user: user} do
      assert Instagram.post_recipe(user, recipe()) == {:error, :not_connected}
    end

    test "errors when the token is stale", %{user: user} do
      user = set_token(user, connected_token(%{"status" => "stale"}))
      assert Instagram.post_recipe(user, recipe()) == {:error, :token_stale}
    end

    test "creates and publishes a media container", %{user: user} do
      user = set_token(user, connected_token())
      assert Instagram.post_recipe(user, recipe()) == {:ok, %{media_id: "stub-media-id"}}
    end

    test "propagates container-create errors with the response body", %{user: user} do
      user = set_token(user, connected_token())

      stub(
        create_media_container: fn _user_id, _token, _url, _caption ->
          {:error, {:http_error, 400, %{"error" => %{"message" => "caption too long"}}}}
        end
      )

      assert {:error, {:http_error, 400, %{"error" => %{"message" => "caption too long"}}}} =
               Instagram.post_recipe(user, recipe())
    end
  end
end
