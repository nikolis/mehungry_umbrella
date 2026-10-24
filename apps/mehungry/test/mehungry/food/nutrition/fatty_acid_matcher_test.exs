defmodule Mehungry.Food.Nutrition.FattyAcidMatcherTest do
  @moduledoc """
  Coverage for `Mehungry.Food.Nutrition.FattyAcidMatcher` — resolving USDA/FDC
  lipid-number notation (`SFA 12:0`, `PUFA 18:2 n-6 c,c`, …) to common names.
  """
  use ExUnit.Case, async: true

  alias Mehungry.Food.Nutrition.FattyAcidMatcher, as: M

  doctest M

  describe "common_name/1 — saturated" do
    test "resolves by carbon count regardless of class prefix formatting" do
      assert M.common_name("SFA 4:0") == "Butyric acid"
      assert M.common_name("SFA 12:0") == "Lauric acid"
      assert M.common_name("SFA 16:0") == "Palmitic acid"
      assert M.common_name("SFA 18:0") == "Stearic acid"
      assert M.common_name("SFA 24:0") == "Lignoceric acid"
    end
  end

  describe "common_name/1 — monounsaturated positional isomers" do
    test "falls back to the dominant isomer when no n-position is given" do
      assert M.common_name("MUFA 16:1 c") == "Palmitoleic acid"
      assert M.common_name("MUFA 18:1 c") == "Oleic acid"
      assert M.common_name("MUFA 22:1 c") == "Erucic acid"
    end

    test "disambiguates by n-position" do
      assert M.common_name("MUFA 18:1 n-7") == "Vaccenic acid"
      assert M.common_name("MUFA 22:1 n-9") == "Erucic acid"
      assert M.common_name("MUFA 22:1 n-11") == "Cetoleic acid"
      assert M.common_name("MUFA 24:1 c") == "Nervonic acid"
    end
  end

  describe "common_name/1 — polyunsaturated" do
    test "distinguishes omega-3 vs omega-6 at the same lipid number" do
      assert M.common_name("PUFA 18:3 n-3 c,c,c (ALA)") == "Alpha-Linolenic acid"
      assert M.common_name("PUFA 18:3 n-6 c,c,c") == "Gamma-Linolenic acid"
    end

    test "resolves the named long-chain omega-3s" do
      assert M.common_name("PUFA 20:5 n-3 (EPA)") == "Eicosapentaenoic acid"
      assert M.common_name("PUFA 22:5 n-3 (DPA)") == "Docosapentaenoic acid"
      assert M.common_name("PUFA 22:6 n-3 (DHA)") == "Docosahexaenoic acid"
    end

    test "resolves omega-6 arachidonic and linoleic" do
      assert M.common_name("PUFA 18:2 n-6 c,c") == "Linoleic acid"
      assert M.common_name("PUFA 18:2") == "Linoleic acid"
      assert M.common_name("PUFA 20:4") == "Arachidonic acid"
    end
  end

  describe "common_name/1 — trans isomers" do
    test "uses the trans-specific trivial name" do
      assert M.common_name("TFA 18:1 t") == "Elaidic acid"
      assert M.common_name("TFA 16:1 t") == "Palmitelaidic acid"
      assert M.common_name("TFA 18:2 t") == "Linolelaidic acid"
    end

    test "a trans flag with no dedicated name falls back to the cis skeleton" do
      assert M.common_name("TFA 20:1 t") == "Gondoic acid"
    end
  end

  describe "common_name/1 — non-matches" do
    test "returns nil for non fatty-acid names" do
      assert M.common_name("Total Fat") == nil
      assert M.common_name("Fatty Acids, Total Saturated") == nil
      assert M.common_name("Energy") == nil
      assert M.common_name(nil) == nil
    end
  end

  describe "display_name/1" do
    test "annotates with lipid number and omega family" do
      assert M.display_name("PUFA 18:2 n-6 c,c") == "Linoleic acid (C18:2, Omega-6)"
      assert M.display_name("SFA 12:0") == "Lauric acid (C12:0)"
      assert M.display_name("PUFA 20:5 n-3 (EPA)") == "Eicosapentaenoic acid (EPA) (C20:5, Omega-3)"
    end

    test "falls back to a title-cased original for unrecognised names" do
      assert M.display_name("some mystery lipid") == "Some Mystery Lipid"
    end
  end

  describe "match/1" do
    test "returns the parsed descriptor alongside the name" do
      assert %{
               name: "Linoleic acid",
               carbons: 18,
               double_bonds: 2,
               omega: 6,
               omega_family: "Omega-6",
               trans?: false
             } = M.match("PUFA 18:2 n-6 c,c")
    end
  end
end
