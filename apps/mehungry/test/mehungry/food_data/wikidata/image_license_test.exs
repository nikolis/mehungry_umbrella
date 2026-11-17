defmodule Mehungry.FoodData.Wikidata.ImageLicenseTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Wikidata.ImageLicense

  describe "reusable?/1" do
    test "allows CC0, public domain, CC BY, and CC BY-SA (any version)" do
      for code <- ~w(cc0 CC0-1.0 pd pdm cc-by-3.0 cc-by-4.0 cc-by-sa-2.5 cc-by-sa-4.0) do
        assert ImageLicense.reusable?(%{license_code: code}), "expected #{code} to be allowed"
      end

      assert ImageLicense.reusable?(%{license_code: nil, license_name: "Public domain"})
      assert ImageLicense.reusable?(%{license_code: nil, license_name: "CC BY-SA 3.0"})
    end

    test "rejects NonCommercial, NoDerivs, fair-use, and non-free" do
      for code <- ~w(cc-by-nc-4.0 cc-by-nc-sa-3.0 cc-by-nd-4.0 fair-use nonfree) do
        refute ImageLicense.reusable?(%{license_code: code}), "expected #{code} to be rejected"
      end
    end

    test "rejects an unrecognized code (fail-closed)" do
      refute ImageLicense.reusable?(%{license_code: "all rights reserved"})
      refute ImageLicense.reusable?(%{license_code: "copyrighted"})
    end

    test "rejects anything carrying a non-empty Restrictions note, even a free licence" do
      refute ImageLicense.reusable?(%{license_code: "cc-by-sa-3.0", restrictions: "trademarked"})
      # an empty restrictions string does not block a free licence
      assert ImageLicense.reusable?(%{license_code: "cc-by-sa-3.0", restrictions: ""})
    end

    test "rejects when no licence information is present, or a non-map" do
      refute ImageLicense.reusable?(%{})
      refute ImageLicense.reusable?(nil)
    end
  end

  describe "attribution_text/1" do
    test "joins artist, licence, and the Commons source" do
      text =
        ImageLicense.attribution_text(%{artist: "Alvesgaspar", license_name: "CC BY-SA 3.0"})

      assert text == "Alvesgaspar, CC BY-SA 3.0, via Wikimedia Commons"
    end

    test "omits missing parts" do
      assert ImageLicense.attribution_text(%{license_name: "CC0"}) ==
               "CC0, via Wikimedia Commons"

      assert ImageLicense.attribution_text(%{}) == "via Wikimedia Commons"
    end
  end
end
