defmodule MehungryWeb.LocaleTest do
  use ExUnit.Case, async: true

  alias MehungryWeb.Locale

  describe "supported?/1 and defaults" do
    test "en and el are supported, default is en" do
      assert Locale.supported?("en")
      assert Locale.supported?("el")
      refute Locale.supported?("xx")
      refute Locale.supported?(nil)
      assert Locale.default() == "en"
    end
  end

  describe "swap_path/2" do
    test "inserts a locale prefix when the path has none" do
      assert Locale.swap_path("/browse", "el") == "/el/browse"
      assert Locale.swap_path("/foods/tomato", "en") == "/en/foods/tomato"
    end

    test "replaces an existing locale prefix" do
      assert Locale.swap_path("/en/browse", "el") == "/el/browse"
      assert Locale.swap_path("/el/foods/tomato", "en") == "/en/foods/tomato"
    end

    test "prefixes a generic (localizable) first segment" do
      assert Locale.swap_path("/something/else", "el") == "/el/something/else"
    end

    test "leaves non-localized surfaces (admin/nutritionist panels) unprefixed" do
      # These surfaces live on bare, unprefixed routes — their locale is driven
      # by the session/profile, so swap_path must never insert a /:locale prefix.
      assert Locale.swap_path("/professional/users", "el") == "/professional/users"
      assert Locale.swap_path("/nutritionist/clients", "el") == "/nutritionist/clients"
      assert Locale.swap_path("/nutritionist/clients?tab=x", "el") == "/nutritionist/clients?tab=x"
    end

    test "preserves the query string" do
      assert Locale.swap_path("/search?q=rice", "el") == "/el/search?q=rice"
      assert Locale.swap_path("/en/search?q=rice", "el") == "/el/search?q=rice"
    end

    test "root path becomes a bare locale segment" do
      assert Locale.swap_path("/", "el") == "/el"
    end
  end
end
