defmodule Mehungry.FoodData.Gutenberg.Catalog do
  @moduledoc """
  The curated list of **public-domain, English-language** cookbooks on Project
  Gutenberg that the `Mehungry.FoodData.GutenbergImporter` can import from.

  Every title here is old enough to be in the public domain worldwide (no
  licence, no attribution obligation beyond the credit we voluntarily store), so
  — like the USDA MyPlate corpus — we may store, serve, and build on these
  recipes indefinitely.

  Each entry carries the `:format` the `Mehungry.FoodData.Gutenberg.BookParser`
  needs to split the book's plain text into individual recipes:

    * `:numbered` — recipes are delimited by a lone number line (`1`, `2`, …);
      the title is the next line and the directions are prose (no ingredient
      list). e.g. *The Italian Cook Book*.
    * `:heading`  — recipes are delimited by an ALL-CAPS title line, optionally
      followed by an italic original-language subtitle and an **indented**
      ingredient list, then prose directions. e.g. *Simple Italian Cookery*.

  Adding a book is a one-line entry here **after** confirming its structure
  matches one of the two formats (eyeball the raw `text_url/1`) — do not add a
  book whose layout the parser hasn't been validated against, since a bad format
  guess produces garbage recipes for the reviewer to wade through.

  Only the three Italian titles below have been structurally validated. Other
  English public-domain cookbooks exist on Gutenberg (Escoffier, *The Cook's
  Decameron*, *Allied Cookery*, …) but use table-of-contents / page-number
  layouts that need bespoke parsing before they can be listed here.
  """

  @books [
    %{
      id: "24407",
      title: "The Italian Cook Book",
      author: "Maria Gentile",
      cuisine: "Italian",
      format: :numbered
    },
    %{
      id: "6385",
      title: "Simple Italian Cookery",
      author: "Antonia Isola",
      cuisine: "Italian",
      format: :heading
    },
    %{
      id: "43912",
      title: "Practical Italian Recipes for American Kitchens",
      author: "Julia Lovejoy Cuniberti",
      cuisine: "Italian",
      format: :heading
    }
  ]

  @doc "Every catalogued book."
  def books, do: @books

  @doc "The book with this Gutenberg ebook id (string or integer), or `nil`."
  def get(id) do
    id = to_string(id)
    Enum.find(@books, &(&1.id == id))
  end

  @doc "URL of the plain-text (UTF-8) ebook — what `Client.fetch_book/1` downloads."
  def text_url(id), do: "https://www.gutenberg.org/cache/epub/#{id}/pg#{id}.txt"

  @doc "URL of the human-readable ebook landing page — stored as the recipe's `original_url`."
  def book_url(id), do: "https://www.gutenberg.org/ebooks/#{id}"
end
