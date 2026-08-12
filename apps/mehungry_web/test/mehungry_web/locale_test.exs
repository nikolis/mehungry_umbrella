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

    test "leaves a non-locale first segment intact" do
      assert Locale.swap_path("/professional/users", "el") == "/el/professional/users"
    end

    test "preserves the query string" do
      assert Locale.swap_path("/search?q=rice", "el") == "/el/search?q=rice"
      assert Locale.swap_path("/en/search?q=rice", "el") == "/el/search?q=rice"
    end

    test "root path becomes a bare locale segment" do
      assert Locale.swap_path("/", "el") == "/el"
    end
  end

  describe "data_language_name/1" do
    test "maps URL locales to the legacy translation-table language names" do
      assert Locale.data_language_name("el") == "Gr"
      assert Locale.data_language_name("en") == "En"
    end
  end
end
