defmodule Mehungry.Social.PinterestTest do
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures

  alias Mehungry.Accounts
  alias Mehungry.Social.Pinterest
  alias Mehungry.Social.Pinterest.Token

  defmodule EndpointStub do
    def url, do: "https://test.m3hungry.com"
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:mehungry, :pinterest_http_stub)
      Application.delete_env(:mehungry, :endpoint_module)
    end)

    Application.put_env(:mehungry, :endpoint_module, EndpointStub)
    %{user: user_fixture()}
  end

  defp set_token(user, token) do
    {:ok, user} = Accounts.update_user_tokens(user, %{"pinterest_token" => token})
    user
  end

  defp reload_token(user), do: Accounts.get_user!(user.id).pinterest_token

  defp ok_json(status, map), do: {:ok, %HTTPoison.Response{status_code: status, body: Jason.encode!(map)}}

  describe "refresh_user_token/1" do
    test "persists the refreshed token and keeps the refresh token", %{user: user} do
      user = set_token(user, %{"access_token" => "old", "refresh_token" => "r", "scope" => "s"})

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn _url, _body, _headers ->
          ok_json(200, %{"access_token" => "fresh", "expires_in" => 2_592_000})
        end
      )

      assert {:ok, _user} = Pinterest.refresh_user_token(user)

      token = reload_token(user)
      assert token["access_token"] == "fresh"
      assert token["refresh_token"] == "r"
      assert token["status"] == "active"
      assert token["expires_at"]
    end

    test "keeps a rotated refresh token when Pinterest returns one", %{user: user} do
      user = set_token(user, %{"access_token" => "old", "refresh_token" => "r"})

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn _url, _body, _headers ->
          ok_json(200, %{"access_token" => "fresh", "refresh_token" => "r2", "expires_in" => 10})
        end
      )

      assert {:ok, _user} = Pinterest.refresh_user_token(user)
      assert reload_token(user)["refresh_token"] == "r2"
    end

    test "marks the token stale on a 4xx", %{user: user} do
      user = set_token(user, %{"access_token" => "old", "refresh_token" => "dead"})

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn _url, _body, _headers -> ok_json(400, %{"error" => "invalid_grant"}) end
      )

      assert {:error, {:http_error, 400, _}} = Pinterest.refresh_user_token(user)
      assert Token.status(reload_token(user)) == :stale
    end

    test "errors without a refresh token", %{user: user} do
      user = set_token(user, %{"access_token" => "old"})
      assert {:error, :no_refresh_token} = Pinterest.refresh_user_token(user)
    end
  end

  describe "get_boards/1 refresh-on-401" do
    test "refreshes once and retries on a 401", %{user: user} do
      user = set_token(user, %{"access_token" => "stale", "refresh_token" => "r"})
      test_pid = self()

      Application.put_env(:mehungry, :pinterest_http_stub,
        get: fn _url, headers ->
          token = bearer(headers)
          send(test_pid, {:get_called, token})

          if token == "stale" do
            {:ok, %HTTPoison.Response{status_code: 401, body: "{}"}}
          else
            ok_json(200, %{"items" => [%{"id" => "b1", "name" => "Board"}]})
          end
        end,
        post: fn _url, _body, _headers ->
          ok_json(200, %{"access_token" => "fresh", "expires_in" => 2_592_000})
        end
      )

      assert {:ok, [%{"id" => "b1"}]} = Pinterest.get_boards(user)
      assert_received {:get_called, "stale"}
      assert_received {:get_called, "fresh"}
      assert reload_token(user)["access_token"] == "fresh"
    end

    test "returns the 401 error when refresh itself fails", %{user: user} do
      user = set_token(user, %{"access_token" => "stale", "refresh_token" => "dead"})

      Application.put_env(:mehungry, :pinterest_http_stub,
        get: fn _url, _headers -> {:ok, %HTTPoison.Response{status_code: 401, body: "nope"}} end,
        post: fn _url, _body, _headers -> ok_json(400, %{"error" => "invalid_grant"}) end
      )

      assert {:error, {:http_error, 401, "nope"}} = Pinterest.get_boards(user)
    end

    test "not_connected when no token", %{user: user} do
      assert {:error, :not_connected} = Pinterest.get_boards(user)
    end
  end

  describe "create_pin/3 body" do
    test "includes ingredients, steps, image and hashtags in the pin", %{user: user} do
      user = set_token(user, %{"access_token" => "tok", "refresh_token" => "r"})
      test_pid = self()

      recipe = %Mehungry.Food.Recipe{
        id: 42,
        title: "Lemon Pasta",
        description: "Bright and zesty.",
        cooking_time_lower_limit: 20,
        image_url: "https://img.example/lemon.jpg",
        recipe_ingredients: [
          %Mehungry.Food.RecipeIngredient{
            quantity: 200,
            measurement_unit: %{name: "g"},
            ingredient: %{name: "Spaghetti"}
          },
          %Mehungry.Food.RecipeIngredient{
            quantity: 1,
            measurement_unit: %{name: "piece"},
            ingredient: %{name: "Lemon"}
          }
        ],
        steps: [
          %Mehungry.Food.Step{index: 0, title: "Boil", description: "Boil the pasta."},
          %Mehungry.Food.Step{index: 1, description: "Toss with lemon."}
        ],
        recipe_hashtags: [
          %Mehungry.Food.RecipeHashtag{hashtag: %{title: "pasta night"}}
        ]
      }

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn _url, body, _headers ->
          send(test_pid, {:pin_body, Jason.decode!(body)})
          ok_json(201, %{"id" => "pin_1"})
        end
      )

      assert {:ok, %{"id" => "pin_1"}} = Pinterest.create_pin(user, recipe, "board_1")

      assert_received {:pin_body, pin}
      assert pin["title"] == "Lemon Pasta"
      assert pin["media_source"]["url"] == "https://img.example/lemon.jpg"

      description = pin["description"]
      assert description =~ "Ingredients"
      assert description =~ "200 g Spaghetti"
      assert description =~ "1 piece Lemon"
      assert description =~ "Instructions"
      assert description =~ "Boil the pasta."
      assert description =~ "Toss with lemon."
      assert description =~ "#pastanight"
      assert description =~ "#mehungry"
    end

    test "falls back to the brand hashtag when hashtags are not loaded", %{user: user} do
      user = set_token(user, %{"access_token" => "tok", "refresh_token" => "r"})
      test_pid = self()

      recipe = %Mehungry.Food.Recipe{
        id: 7,
        title: "Plain",
        description: "Simple.",
        image_url: "https://img.example/x.jpg",
        recipe_ingredients: %Ecto.Association.NotLoaded{},
        recipe_hashtags: %Ecto.Association.NotLoaded{},
        steps: []
      }

      Application.put_env(:mehungry, :pinterest_http_stub,
        post: fn _url, body, _headers ->
          send(test_pid, {:pin_body, Jason.decode!(body)})
          ok_json(201, %{"id" => "pin_2"})
        end
      )

      assert {:ok, _} = Pinterest.create_pin(user, recipe, "board_1")
      assert_received {:pin_body, pin}
      assert pin["description"] =~ "#mehungry"
    end
  end

  defp bearer(headers) do
    case Enum.find(headers, fn {k, _} -> k == "Authorization" end) do
      {_, "Bearer " <> token} -> token
      _ -> nil
    end
  end
end
