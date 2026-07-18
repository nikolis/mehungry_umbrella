defmodule Mehungry.Instagram.TokenTest do
  use ExUnit.Case, async: true

  alias Mehungry.Instagram.Token

  @now ~U[2026-07-18 12:00:00Z]

  defp iso(dt), do: DateTime.to_iso8601(dt)

  describe "status/2" do
    test "nil and empty map are not connected" do
      assert Token.status(nil, @now) == :not_connected
      assert Token.status(%{}, @now) == :not_connected
    end

    test "maps holding Instagram error JSON classify as :error" do
      assert Token.status(%{"error_type" => "OAuthException", "user_id" => "1"}, @now) == :error
      assert Token.status(%{"error" => %{"message" => "nope"}}, @now) == :error
    end

    test "legacy token without expires_at is connected" do
      assert Token.status(%{"access_token" => "t", "user_id" => "1"}, @now) == :connected
    end

    test "explicit stale status wins" do
      token = %{"access_token" => "t", "status" => "stale"}
      assert Token.status(token, @now) == :stale
    end

    test "past expiry is stale, near expiry is expiring, far expiry is connected" do
      base = %{"access_token" => "t"}

      past = Map.put(base, "expires_at", iso(DateTime.add(@now, -1, :day)))
      near = Map.put(base, "expires_at", iso(DateTime.add(@now, 3, :day)))
      far = Map.put(base, "expires_at", iso(DateTime.add(@now, 40, :day)))

      assert Token.status(past, @now) == :stale
      assert Token.status(near, @now) == :expiring
      assert Token.status(far, @now) == :connected
    end
  end

  describe "build/3" do
    test "computes absolute expiry and stamps lifecycle fields" do
      response = %{
        "access_token" => "long",
        "token_type" => "bearer",
        "expires_in" => 5_184_000
      }

      token = Token.build(response, 123, @now)

      assert token["access_token"] == "long"
      assert token["user_id"] == "123"
      assert token["status"] == "active"
      assert token["obtained_at"] == iso(@now)
      assert token["expires_at"] == iso(DateTime.add(@now, 5_184_000, :second))
    end

    test "missing expires_in leaves expires_at nil" do
      token = Token.build(%{"access_token" => "long"}, "1", @now)
      assert token["expires_at"] == nil
      assert Token.status(token, @now) == :connected
    end
  end

  describe "refreshable?/2" do
    test "false for tokens younger than 24h" do
      token = Token.build(%{"access_token" => "t", "expires_in" => 5_184_000}, "1", @now)
      refute Token.refreshable?(token, DateTime.add(@now, 2, :hour))
    end

    test "true once the token is at least 24h old" do
      token = Token.build(%{"access_token" => "t", "expires_in" => 5_184_000}, "1", @now)
      assert Token.refreshable?(token, DateTime.add(@now, 25, :hour))
    end

    test "true for legacy tokens without timestamps" do
      assert Token.refreshable?(%{"access_token" => "t"}, @now)
    end

    test "false for stale, error, and empty tokens" do
      refute Token.refreshable?(%{"access_token" => "t", "status" => "stale"}, @now)
      refute Token.refreshable?(%{"error_type" => "OAuthException"}, @now)
      refute Token.refreshable?(%{}, @now)
    end
  end
end
