defmodule Mehungry.Food.SpeciesIconsTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.SpeciesIcons

  describe "icon_for/1" do
    test "keyword match on the name wins" do
      assert SpeciesIcons.icon_for(%{name: "Apple"}) == "🍎"
      assert SpeciesIcons.icon_for(%{name: "Spinach"}) == "🥬"
      assert SpeciesIcons.icon_for(%{name: "Cattle"}) == "🐄"
      assert SpeciesIcons.icon_for(%{name: "Salmon"}) == "🐟"
    end

    test "matching is case-insensitive and scans variety/alternative_name too" do
      assert SpeciesIcons.icon_for(%{name: "TOMATO", variety: nil, alternative_name: nil}) == "🍅"

      assert SpeciesIcons.icon_for(%{name: "Unknownus plantae", alternative_name: "wild carrot"}) ==
               "🥕"
    end

    test "more specific keyword beats the generic one it precedes" do
      # "strawberry" (🍓) is listed before the generic "berry"; both would match
      # the generic, so order must resolve to the specific fruit here.
      assert SpeciesIcons.icon_for(%{name: "Blueberry"}) == "🫐"
    end

    test "a non-empty override always wins over the derived default" do
      assert SpeciesIcons.icon_for(%{name: "Apple", icon: "🦄"}) == "🦄"
    end

    test "blank/nil override falls through to the derived default" do
      assert SpeciesIcons.icon_for(%{name: "Apple", icon: ""}) == "🍎"
      assert SpeciesIcons.icon_for(%{name: "Apple", icon: nil}) == "🍎"
    end

    test "falls back to family emoji when no keyword matches" do
      assert SpeciesIcons.icon_for(%{name: "Zzzxyz", family: "Solanaceae"}) == "🍅"
      # case/whitespace-insensitive family lookup
      assert SpeciesIcons.icon_for(%{name: "Zzzxyz", family: " poaceae "}) == "🌾"
    end

    test "falls back to the generic plate on a total miss" do
      assert SpeciesIcons.icon_for(%{name: "Zzzxyz", family: nil}) == "🥗"
      assert SpeciesIcons.icon_for(%{name: "Zzzxyz", family: "NoSuchFamily"}) == "🥗"
    end
  end
end
