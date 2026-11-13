defmodule Mehungry.Literature.LicenseTest do
  use ExUnit.Case, async: true

  alias Mehungry.Literature.License

  describe "normalize/1" do
    test "canonicalizes common CC spellings" do
      assert License.normalize("CC BY") == "cc-by"
      assert License.normalize("cc-by") == "cc-by"
      assert License.normalize("CC BY-NC-ND") == "cc-by-nc-nd"
      assert License.normalize("cc by nc") == "cc-by-nc"
      assert License.normalize("CC BY-SA") == "cc-by-sa"
      assert License.normalize("CC0") == "cc0"
    end

    test "derives from a CC deed URL" do
      assert License.normalize("https://creativecommons.org/licenses/by/4.0/") == "cc-by"
      assert License.normalize("https://creativecommons.org/licenses/by-nc-nd/4.0/") == "cc-by-nc-nd"
      assert License.normalize("https://creativecommons.org/publicdomain/zero/1.0/") == "cc0"
    end

    test "unknown / blank / nil" do
      assert License.normalize(nil) == "unknown"
      assert License.normalize("") == "unknown"
      assert License.normalize("All rights reserved") == "other"
    end
  end

  describe "reusable?/1 — only CC0 / CC BY / CC BY-SA display verbatim" do
    test "reusable" do
      for l <- ~w(cc0 cc-by cc-by-sa), do: assert(License.reusable?(l), "#{l} should be reusable")
      assert License.reusable?("CC BY")
    end

    test "not reusable" do
      for l <- ~w(cc-by-nc cc-by-nc-sa cc-by-nd cc-by-nc-nd other unknown) do
        refute License.reusable?(l), "#{l} must not be reusable"
      end

      refute License.reusable?(nil)
      refute License.reusable?("CC BY-NC-ND")
    end
  end

  describe "deed_url/2" do
    test "prefers a stored url, else derives from the canonical value" do
      assert License.deed_url("cc-by", "https://example.com/lic") == "https://example.com/lic"
      assert License.deed_url("cc-by", nil) == "https://creativecommons.org/licenses/by/4.0/"
      assert License.deed_url("unknown", nil) == nil
    end
  end
end
