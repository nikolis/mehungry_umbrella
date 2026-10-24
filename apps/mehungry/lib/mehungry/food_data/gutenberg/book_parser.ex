defmodule Mehungry.FoodData.Gutenberg.BookParser do
  @moduledoc """
  Splits a Project Gutenberg cookbook's plain text into a list of individual
  recipe maps, using the per-book `:format` from
  `Mehungry.FoodData.Gutenberg.Catalog`.

  This is the Gutenberg analogue of the MyPlate API's per-recipe JSON: it turns
  one unstructured book into structured recipe candidates that
  `Mehungry.FoodData.GutenbergImporter` then maps into `Recipe` attrs. Because a
  century-old cookbook's layout is far looser than a JSON API, extraction is
  deliberately **best-effort** — the import flow is human-in-the-loop, so the
  admin fixes or skips anything the heuristics got wrong.

  ## Output

  `parse/2` → `[%{index, title, subtitle, ingredient_lines, directions, raw}]`,
  one entry per detected recipe, `index` 1-based in reading order:

    * `title`            — the recipe heading (e.g. `"PARADISE SOUP"`)
    * `subtitle`         — the italic original-language name if present, else `nil`
    * `ingredient_lines` — the verbatim indented ingredient lines (may be `[]`;
      numbered-prose books list ingredients inside the directions, not separately)
    * `directions`       — the reflowed prose body
    * `raw`              — the verbatim block, shown beside the form for comparison

  ## Formats

    * `:numbered` — blocks delimited by a lone number line; title is the next
      non-blank line, the rest is prose directions.
    * `:heading`  — blocks delimited by an ALL-CAPS title line; an optional
      italic subtitle and an indented ingredient list lead the prose. Headings
      with an empty body (section labels like `SOUPS`) are dropped.

  Pure and DB-free.
  """

  # A recipe heading in `:heading` books: an un-indented line, ≤60 chars, whose
  # letters are all uppercase (digits/punctuation/accents allowed), with at least
  # one letter. Catches "PARADISE SOUP", "EGGS ALL' AURORA"; rejects prose and
  # Title-case section labels (those are handled as trailing noise).
  @heading_re ~r/^[^a-zà-ÿ\s][^a-zà-ÿ]*$/u

  # A lone recipe number in `:numbered` books.
  @number_re ~r/^\s*(\d{1,4})\.?\s*$/

  # An italic / parenthesised original-language subtitle line:
  # "(_Brodo di Carne_)" or "_Minestra del Paradiso_".
  @subtitle_re ~r/^\(?_.+_\)?$/

  # Back-matter headings that mark the end of the recipe body (index, glossary…).
  @back_matter_re ~r/^\s*(INDEX|GLOSSARY|APPENDIX|TRANSCRIBER)/

  # Front-matter / non-recipe headings to drop even when they have a body
  # (a table of contents, a preface, a copyright line…). Matched against the
  # emphasis-stripped, upcased title.
  @front_matter ~w(
    CONTENTS PREFACE INTRODUCTION FOREWORD SUGGESTIONS DEDICATION
    ACKNOWLEDGMENTS ACKNOWLEDGEMENTS NOTE NOTES COPYRIGHT COPYRIGHTED
    TITLE AUTHOR PUBLISHER ILLUSTRATIONS
  )

  @doc "Parses `text` (a full Gutenberg ebook) into recipe maps per `format`."
  def parse(text, format) when is_binary(text) do
    text
    # Gutenberg ships CRLF; normalise so un-indented/heading checks don't trip on \r.
    |> String.replace("\r\n", "\n")
    |> strip_boilerplate()
    |> truncate_at_back_matter()
    |> split_blocks(format)
    |> Enum.map(&parse_block/1)
    |> Enum.reject(&empty_recipe?/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {recipe, index} -> Map.put(recipe, :index, index) end)
  end

  # ── boilerplate / back-matter ───────────────────────────────────────────────

  # Keep only the text between the Gutenberg START/END license markers.
  defp strip_boilerplate(text) do
    body =
      case String.split(text, ~r/\*\*\*\s*START OF.*?\*\*\*/s, parts: 2) do
        [_, rest] -> rest
        [only] -> only
      end

    case String.split(body, ~r/\*\*\*\s*END OF.*?\*\*\*/s, parts: 2) do
      [kept, _] -> kept
      [only] -> only
    end
  end

  # Drop everything from the first back-matter heading onward (the book's own
  # index / glossary isn't recipe content and would otherwise glue onto the last
  # recipe's directions).
  defp truncate_at_back_matter(text) do
    text
    |> String.split("\n")
    |> Enum.take_while(fn line -> not Regex.match?(@back_matter_re, line) end)
    |> Enum.join("\n")
  end

  # ── block splitting ─────────────────────────────────────────────────────────

  defp split_blocks(text, :numbered) do
    lines = String.split(text, "\n")

    # A block starts at each lone-number line and runs to the next one. The
    # number line itself is dropped; everything up to the first number is
    # front-matter and discarded.
    lines
    |> chunk_by_delimiter(&Regex.match?(@number_re, &1))
    |> Enum.map(&Enum.drop(&1, 1))
  end

  defp split_blocks(text, :heading) do
    lines = String.split(text, "\n")

    # A block starts at each ALL-CAPS heading line and keeps the heading as its
    # first line (the title). Text before the first heading is front-matter.
    lines
    |> chunk_by_delimiter(&heading_line?/1)
  end

  # Splits `lines` into chunks, each beginning at a line for which `delimiter?`
  # is true. Lines before the first delimiter are discarded.
  defp chunk_by_delimiter(lines, delimiter?) do
    lines
    |> Enum.reduce([], fn line, acc ->
      cond do
        delimiter?.(line) -> [[line] | acc]
        acc == [] -> acc
        true -> [[line | hd(acc)] | tl(acc)]
      end
    end)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp heading_line?(line) do
    trimmed = String.trim(line)

    # Un-indented (a leading space means it's an indented ingredient line or a
    # centred TOC entry, not a heading).
    line == trimmed and
      trimmed != "" and
      String.length(trimmed) <= 60 and
      Regex.match?(@heading_re, trimmed) and
      String.match?(trimmed, ~r/\p{L}/u)
  end

  # ── block → recipe ──────────────────────────────────────────────────────────

  defp parse_block([]), do: empty()

  defp parse_block(block_lines) do
    raw = block_lines |> Enum.join("\n") |> String.trim()

    {title, rest} = take_title(block_lines)
    {subtitle, rest} = take_subtitle(rest)
    {ingredient_lines, rest} = take_ingredients(rest)
    directions = reflow(rest)

    %{
      title: title,
      subtitle: subtitle,
      ingredient_lines: ingredient_lines,
      directions: directions,
      raw: raw
    }
  end

  # Title is the first non-blank line.
  defp take_title(lines) do
    case drop_leading_blanks(lines) do
      [] -> {"", []}
      [title | rest] -> {String.trim(title), rest}
    end
  end

  # An italic/parenthesised line immediately after the title is the original-
  # language subtitle; consume it. Otherwise leave `rest` untouched.
  defp take_subtitle(lines) do
    case drop_leading_blanks(lines) do
      [maybe | rest] ->
        t = String.trim(maybe)
        if Regex.match?(@subtitle_re, t), do: {strip_emphasis(t), rest}, else: {nil, lines}

      [] ->
        {nil, lines}
    end
  end

  # The leading maximal run of indented lines is the ingredient list (prose in
  # these books starts at column 0). Blank lines before it are skipped; the run
  # ends at the first un-indented content line. Italic-only indented lines
  # (trailing attributions) are not treated as ingredients.
  defp take_ingredients(lines) do
    lines = drop_leading_blanks(lines)

    {indented, rest} =
      Enum.split_while(lines, fn line ->
        String.trim(line) != "" and indented?(line)
      end)

    ingredient_lines =
      indented
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or Regex.match?(@subtitle_re, &1)))

    {ingredient_lines, rest}
  end

  defp indented?(line), do: String.match?(line, ~r/^\s{2,}\S/)

  # Reflow the prose body: collapse runs of whitespace, keep paragraph breaks.
  # Trailing short Title-case/ALL-CAPS section labels (e.g. a "Vegetables" header
  # that fell into the previous recipe) are dropped.
  defp reflow(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> drop_trailing_blanks()
    |> drop_trailing_section_label()
    |> Enum.join("\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # If the body ends with a lone short heading-ish line (a section label the
  # heading splitter didn't catch because it was Title-case, not ALL-CAPS), drop
  # it along with the blank run before it.
  defp drop_trailing_section_label(lines) do
    case drop_trailing_blanks(lines) do
      [] ->
        []

      trimmed ->
        last = List.last(trimmed)

        if section_label?(last) do
          trimmed |> Enum.drop(-1) |> drop_trailing_blanks()
        else
          trimmed
        end
    end
  end

  # A short (≤3 words), capitalised, sentence-less line — a plausible stray
  # section header.
  defp section_label?(line) do
    words = String.split(line, ~r/\s+/, trim: true)

    length(words) in 1..3 and
      not String.ends_with?(line, [".", "!", "?", ",", ":", ";"]) and
      Enum.all?(words, &String.match?(&1, ~r/^\p{Lu}/u))
  end

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp drop_leading_blanks(lines), do: Enum.drop_while(lines, &(String.trim(&1) == ""))

  defp drop_trailing_blanks(lines) do
    lines |> Enum.reverse() |> Enum.drop_while(&(String.trim(&1) == "")) |> Enum.reverse()
  end

  defp strip_emphasis(text) do
    text
    |> String.replace(~r/^\(|\)$/, "")
    |> String.replace("_", "")
    |> String.trim()
  end

  # A recipe with no title and no body is not worth reviewing (a bare section
  # header, or splitter noise), and neither is a known front-matter heading.
  defp empty_recipe?(%{title: title, directions: directions, ingredient_lines: ings}) do
    String.trim(to_string(title)) == "" or
      front_matter?(title) or
      (String.trim(to_string(directions)) == "" and ings == [])
  end

  defp front_matter?(title) do
    normalized = title |> strip_emphasis() |> String.upcase()

    Enum.any?(@front_matter, fn word ->
      normalized == word or String.starts_with?(normalized, word <> " ") or
        String.starts_with?(normalized, word <> ",")
    end)
  end

  defp empty, do: %{title: "", subtitle: nil, ingredient_lines: [], directions: "", raw: ""}
end
