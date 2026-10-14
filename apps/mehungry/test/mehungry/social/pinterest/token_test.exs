defmodule Mehungry.Social.Pinterest.TokenTest do
  use ExUnit.Case, async: true

  alias Mehungry.Social.Pinterest.Token

  describe "build/1" do
    test "computes expires_at from expires_in (seconds)" do
      now = ~U[2026-10-14 10:00:00Z]

      token =
        Token.build(
          %{"access_token" => "a", "refresh_token" => "r", "expires_in" => 2_592_000},
          now
        )

      assert token["access_token"] == "a"
      assert token["refresh_token"] == "r"
      assert token["status"] == "active"
      assert {:ok, expires_at, _} = DateTime.from_iso8601(token["expires_at"])
      assert DateTime.diff(expires_at, now, :day) == 30
    end

    test "normalizes a legacy unix-integer expires_at to ISO8601" do
      unix = DateTime.to_unix(~U[2026-11-13 10:00:00Z])

      token = Token.build(%{"access_token" => "a", "refresh_token" => "r", "expires_at" => unix})

      assert token["expires_at"] == "2026-11-13T10:00:00Z"
    end

    test "leaves expires_at nil when neither expires_in nor expires_at present" do
      token = Token.build(%{"access_token" => "a", "refresh_token" => "r"})
      assert token["expires_at"] == nil
    end
  end

  describe "status/2" do
    test "empty map is not_connected" do
      assert Token.status(%{}) == :not_connected
    end

    test "missing access_token is not_connected" do
      assert Token.status(%{"refresh_token" => "r"}) == :not_connected
    end

    test "error map is error" do
      assert Token.status(%{"access_token" => "a", "error" => "invalid_grant"}) == :error
    end

    test "status stale is stale" do
      assert Token.status(%{"access_token" => "a", "status" => "stale"}) == :stale
    end

    test "no expiry is connected" do
      assert Token.status(%{"access_token" => "a"}) == :connected
    end

    test "classifies by expiry window" do
      now = ~U[2026-10-14 10:00:00Z]
      far = DateTime.to_iso8601(DateTime.add(now, 30, :day))
      soon = DateTime.to_iso8601(DateTime.add(now, 3, :day))
      past = DateTime.to_iso8601(DateTime.add(now, -1, :day))

      assert Token.status(%{"access_token" => "a", "expires_at" => far}, now) == :connected
      assert Token.status(%{"access_token" => "a", "expires_at" => soon}, now) == :expiring
      assert Token.status(%{"access_token" => "a", "expires_at" => past}, now) == :stale
    end
  end

  describe "expires_at/1" do
    test "parses ISO8601" do
      assert Token.expires_at(%{"expires_at" => "2026-11-13T10:00:00Z"}) ==
               ~U[2026-11-13 10:00:00Z]
    end

    test "parses a legacy unix integer" do
      unix = DateTime.to_unix(~U[2026-11-13 10:00:00Z])
      assert Token.expires_at(%{"expires_at" => unix}) == ~U[2026-11-13 10:00:00Z]
    end

    test "nil when absent/unparseable" do
      assert Token.expires_at(%{}) == nil
      assert Token.expires_at(%{"expires_at" => "garbage"}) == nil
    end
  end

  describe "refreshable?/2" do
    test "true with a refresh token and a usable access token" do
      assert Token.refreshable?(%{"access_token" => "a", "refresh_token" => "r"})
    end

    test "true even when the access token is expired (refresh token outlives it)" do
      now = ~U[2026-10-14 10:00:00Z]
      past = DateTime.to_iso8601(DateTime.add(now, -1, :day))

      assert Token.refreshable?(
               %{"access_token" => "a", "refresh_token" => "r", "expires_at" => past},
               now
             )
    end

    test "false without a refresh token" do
      refute Token.refreshable?(%{"access_token" => "a"})
      refute Token.refreshable?(%{"access_token" => "a", "refresh_token" => ""})
    end

    test "false when marked stale or an error map" do
      refute Token.refreshable?(%{"access_token" => "a", "refresh_token" => "r", "status" => "stale"})
      refute Token.refreshable?(%{"access_token" => "a", "refresh_token" => "r", "error" => "x"})
    end

    test "false when not connected" do
      refute Token.refreshable?(%{"refresh_token" => "r"})
      refute Token.refreshable?(%{})
    end
  end
end
