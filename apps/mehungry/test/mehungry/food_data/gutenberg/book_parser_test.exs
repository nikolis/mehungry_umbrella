defmodule Mehungry.FoodData.Gutenberg.BookParserTest do
  @moduledoc """
  Covers the pure, DB-free splitting of a Gutenberg cookbook into recipes:
  boilerplate stripping, the `:numbered` and `:heading` formats, indented
  ingredient-list extraction, subtitle capture, and front/back-matter dropping.
  """
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Gutenberg.BookParser

  # Wraps `body` in the Gutenberg START/END license markers (CRLF, as shipped).
  defp book(body) do
    ("*** START OF THE PROJECT GUTENBERG EBOOK TEST ***\n" <>
       body <> "\n*** END OF THE PROJECT GUTENBERG EBOOK TEST ***\n")
    |> String.replace("\n", "\r\n")
  end

  describe ":heading format" do
    @heading_body """
    CONTENTS

    Soups
    Sauces


    SOUPS


    BEEF SOUP STOCK
    (_Brodo di Carne_)

      1 pound of round of beef
      2 quarts of water
      Parsley

    Boil the beef and vegetables over a slow fire. Skim occasionally.


    CHICKEN BROTH
    (_Brodo di Capone_)

    This is made like the meat stock, substituting a fowl.
    """

    test "extracts recipes, subtitle, and the indented ingredient list" do
      recipes = BookParser.parse(book(@heading_body), :heading)

      titles = Enum.map(recipes, & &1.title)
      # CONTENTS (front matter) and SOUPS (empty section header) are dropped.
      assert titles == ["BEEF SOUP STOCK", "CHICKEN BROTH"]

      beef = Enum.find(recipes, &(&1.title == "BEEF SOUP STOCK"))
      assert beef.subtitle == "Brodo di Carne"

      assert beef.ingredient_lines == [
               "1 pound of round of beef",
               "2 quarts of water",
               "Parsley"
             ]

      assert beef.directions =~ "Boil the beef"
      # The ingredient lines are not duplicated into the directions.
      refute beef.directions =~ "1 pound of round of beef"
    end

    test "a recipe with no ingredient list still parses (prose only)" do
      recipes = BookParser.parse(book(@heading_body), :heading)
      chicken = Enum.find(recipes, &(&1.title == "CHICKEN BROTH"))

      assert chicken.ingredient_lines == []
      assert chicken.directions =~ "substituting a fowl"
    end

    test "indexes recipes 1-based in reading order" do
      assert [%{index: 1}, %{index: 2}] = BookParser.parse(book(@heading_body), :heading)
    end
  end

  describe ":numbered format" do
    @numbered_body """
    Front matter blurb that should be ignored.


    1

    BROTH

    (Brodo)

    To obtain good broth the meat must be put in cold water.


    2

    BREAD SOUP

    This nutritious soup uses stale bread, eggs, and grated cheese.


    INDEX

    Broth ..... 1
    """

    test "splits on lone number lines; title is the next line, body is prose" do
      recipes = BookParser.parse(book(@numbered_body), :numbered)

      assert Enum.map(recipes, & &1.title) == ["BROTH", "BREAD SOUP"]
      broth = hd(recipes)
      assert broth.ingredient_lines == []
      assert broth.directions =~ "put in cold water"
    end

    test "stops at the book's own INDEX back-matter" do
      recipes = BookParser.parse(book(@numbered_body), :numbered)
      refute Enum.any?(recipes, &(&1.title =~ "INDEX"))
      assert length(recipes) == 2
    end
  end

  test "empty / markerless text yields no recipes" do
    assert BookParser.parse("", :numbered) == []
    assert BookParser.parse("just some prose, no recipes", :heading) == []
  end
end
