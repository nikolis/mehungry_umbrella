defmodule Mehungry.BetaSignupsTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.BetaSignups
  alias Mehungry.BetaSignups.BetaSignup

  describe "create_beta_signup/1" do
    test "stores email, canonical email and a token" do
      assert {:ok, %BetaSignup{} = s} = BetaSignups.create_beta_signup(%{"email" => "Tester@Example.com"})
      assert s.email == "Tester@Example.com"
      assert s.canonical_email == "tester@example.com"
      assert is_binary(s.unsubscribe_token) and byte_size(s.unsubscribe_token) > 20
    end

    test "tokens are unique across signups" do
      {:ok, a} = BetaSignups.create_beta_signup(%{"email" => "a@example.com"})
      {:ok, b} = BetaSignups.create_beta_signup(%{"email" => "b@example.com"})
      refute a.unsubscribe_token == b.unsubscribe_token
    end

    test "rejects an invalid email" do
      assert {:error, changeset} = BetaSignups.create_beta_signup(%{"email" => "nope"})
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
    end

    test "defaults platforms to all when none given (programmatic create)" do
      {:ok, s} = BetaSignups.create_beta_signup(%{"email" => "a@example.com"})
      assert s.platforms == ["android", "ios", "web"]
    end

    test "stores the selected platforms" do
      {:ok, s} =
        BetaSignups.create_beta_signup(%{"email" => "a@example.com", "platforms" => ["ios", "web"]})

      assert s.platforms == ["ios", "web"]
    end

    test "drops the hidden blank entry from the checkbox group" do
      {:ok, s} =
        BetaSignups.create_beta_signup(%{"email" => "a@example.com", "platforms" => ["", "android"]})

      assert s.platforms == ["android"]
    end

    test "rejects an empty platform selection" do
      assert {:error, changeset} =
               BetaSignups.create_beta_signup(%{"email" => "a@example.com", "platforms" => [""]})

      assert %{platforms: ["select at least one platform"]} = errors_on(changeset)
    end

    test "rejects an unknown platform" do
      assert {:error, changeset} =
               BetaSignups.create_beta_signup(%{"email" => "a@example.com", "platforms" => ["desktop"]})

      assert Keyword.has_key?(changeset.errors, :platforms)
    end

    test "dedupes gmail aliases via canonical email" do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "john.doe@gmail.com"})

      assert {:error, changeset} =
               BetaSignups.create_beta_signup(%{"email" => "johndoe+beta@googlemail.com"})

      assert %{canonical_email: ["is already registered"]} = errors_on(changeset)
    end
  end

  describe "listing / counting" do
    test "list + count reflect inserts" do
      assert BetaSignups.count() == 0
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "a@example.com"})
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "b@example.com"})
      assert BetaSignups.count() == 2
      assert length(BetaSignups.list_beta_signups()) == 2
    end
  end

  describe "removal" do
    test "remove_by_email removes a matching canonical email" do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "john.doe@gmail.com"})
      # alias resolves to the same canonical email
      assert {:ok, 1} = BetaSignups.remove_by_email("JohnDoe@gmail.com")
      assert BetaSignups.count() == 0
    end

    test "remove_by_email is a no-op when nothing matches" do
      assert {:ok, 0} = BetaSignups.remove_by_email("ghost@example.com")
    end

    test "remove_by_token removes and returns the email" do
      {:ok, s} = BetaSignups.create_beta_signup(%{"email" => "a@example.com"})
      assert BetaSignups.remove_by_token(s.unsubscribe_token) == "a@example.com"
      assert BetaSignups.count() == 0
    end

    test "remove_by_token returns nil for an unknown token" do
      assert BetaSignups.remove_by_token("bogus") == nil
    end
  end

  describe "version send tracking" do
    test "record_send links the matching signup and is idempotent per version" do
      {:ok, s} = BetaSignups.create_beta_signup(%{"email" => "t@example.com"})

      assert {:ok, row} = BetaSignups.record_send("t@example.com", "1.0.0")
      assert row.beta_signup_id == s.id
      assert row.version == "1.0.0"

      # resending the same version is a no-op (on_conflict: :nothing)
      assert {:ok, _} = BetaSignups.record_send("t@example.com", "1.0.0")
      assert length(BetaSignups.list_sends()) == 1
    end

    test "record_send matches signups through canonical email (gmail alias)" do
      {:ok, s} = BetaSignups.create_beta_signup(%{"email" => "john.doe@gmail.com"})
      {:ok, row} = BetaSignups.record_send("johndoe+beta@googlemail.com", "2.0.0")
      assert row.beta_signup_id == s.id
    end

    test "versions_by_tester groups versions per canonical email, most recent first" do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "t@example.com"})
      {:ok, _} = BetaSignups.record_send("t@example.com", "1.0.0")
      {:ok, _} = BetaSignups.record_send("t@example.com", "1.1.0")

      versions = BetaSignups.versions_by_tester()
      assert versions["t@example.com"] == ["1.1.0", "1.0.0"]
    end

    test "signups_missing_version returns only testers not sent that version" do
      {:ok, _} = BetaSignups.create_beta_signup(%{"email" => "got@example.com"})
      {:ok, missing} = BetaSignups.create_beta_signup(%{"email" => "missing@example.com"})
      {:ok, _} = BetaSignups.record_send("got@example.com", "3.0.0")

      result = BetaSignups.signups_missing_version("3.0.0")
      assert Enum.map(result, & &1.id) == [missing.id]

      # nobody has 4.0.0 yet → both are missing
      assert length(BetaSignups.signups_missing_version("4.0.0")) == 2
    end

    test "signups_missing_version can restrict to a platform" do
      {:ok, _} =
        BetaSignups.create_beta_signup(%{"email" => "android@example.com", "platforms" => ["android"]})

      {:ok, _} =
        BetaSignups.create_beta_signup(%{"email" => "web@example.com", "platforms" => ["web"]})

      # only the Android tester is "missing" an Android build
      result = BetaSignups.signups_missing_version("1.0.0", "android")
      assert Enum.map(result, & &1.email) == ["android@example.com"]
    end
  end
end
