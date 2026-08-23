defmodule Mehungry.FoodData.GlycemicIndex.PdfReferenceParser do
  @moduledoc """
  **Internal verification oracle only** — parses the *published* International Tables
  of Glycemic Index PDFs (`studies/SupplementalTable{1,2}.pdf`) into structured
  reference rows so the re-derivation harness can check the values *we* independently
  extract from primary papers against the published ones.

  This is **not an ingest path.** Under the path-B pivot (see
  `docs/science/glycemic_index_licensing.md`) the compilation is never a data source —
  it is only a private measuring stick. The `studies/` PDFs are git-ignored and must
  never be committed, served, or ingested-as-served.

  ## How it parses

  `pdftotext -layout` renders each data row as one line anchored by the leading **food
  number** that also carries the `GI±SEM` token (`"20±4"`). Columns are recovered by
  splitting on runs of 2+ spaces and anchoring off the unambiguous **year** (`19xx`/
  `20xx`, maybe `*`-suffixed) and `±` tokens:

      | 1 | Belgium | 2010* | 20±4 | 6 | Normal, 10 | 25 | 54.4 | Glucose, 2h | ... | 1 |
        №   country   year    gi±sem  gl  subjects    carb portion ref_food        ref

  Short food names ride inline (token between № and country); long/wrapped names are
  recovered from the left column of the lines just above the value line. All-caps lines
  are carried down as the `category`. The `ref` code is the trailing token: a bare
  integer points at the *main article's* bibliography (a real paper), while `UO<n>`
  marks an **unpublished observation** (Sydney University GI Service, INQUIS, …) with no
  primary paper behind it — those are un-re-derivable and flagged `unpublished: true`.

  Requires the `pdftotext` binary (poppler-utils) on `PATH`.
  """

  @value_line ~r/^\s+(?<num>\d{1,4})\s+.*\d{1,3}±/u
  @year ~r/^(?:19|20)\d{2}\*?$/
  @gi ~r/^(?<gi>\d{1,3}(?:\.\d+)?)±(?<sem>\d{1,3}(?:\.\d+)?)/u
  @all_caps ~r/^[A-Z][A-Z &,'\/\-]{3,}$/

  @doc """
  Parse a Supplemental-Table PDF at `path` into reference-row maps. `opts[:table]` is
  stamped on each row (`"table1"` default | `"table2"`). Returns `{:ok, rows}` or
  `{:error, reason}` (e.g. `:pdftotext_missing`).
  """
  def parse(path, opts \\ []) do
    table = Keyword.get(opts, :table, "table1")

    with :ok <- ensure_pdftotext(),
         {:ok, text} <- pdftotext(path) do
      {:ok, parse_text(text, table)}
    end
  end

  @doc "Same as `parse/2` but on already-extracted layout text (used in tests)."
  def parse_text(text, table \\ "table1") do
    # Process each PDF page (form-feed separated) independently so a row's wrapped
    # name can never claim lines across a page break — where the running header/footer
    # furniture lives. Category persists across pages.
    text
    |> String.replace("\r\n", "\n")
    |> String.split("\f")
    |> Enum.reduce({[], nil}, fn page, {acc, category} ->
      {rows, category} = parse_page(page, table, category)
      {acc ++ rows, category}
    end)
    |> elem(0)
  end

  defp parse_page(page, table, category0) do
    lines = String.split(page, "\n")
    value_idx = for {l, i} <- Enum.with_index(lines), Regex.match?(@value_line, l), do: i
    n = length(lines)

    value_idx
    |> neighbours(n)
    |> Enum.reduce({[], category0}, fn {pi, i, ni}, {acc, category} ->
      category = latest_category(lines, pi + 1, i, category)
      row = build_row(lines, pi, i, ni, category, table)
      {[row | acc], category}
    end)
    |> then(fn {rows, category} -> {Enum.reverse(rows), category} end)
  end

  # Zip each value-line index with its previous (-1 sentinel) and next (n sentinel)
  # value line, so a row can claim only its half of the gap to each neighbour.
  defp neighbours([], _n), do: []

  defp neighbours(idx, n) do
    prev = [-1 | idx]
    next = tl(idx) ++ [n]
    Enum.zip([prev, idx, next])
  end

  # ── Row assembly ─────────────────────────────────────────────────────────────

  defp build_row(lines, pi, i, ni, category, table) do
    line = Enum.at(lines, i)
    tokens = split_cols(line)
    ["" <> _num = num | rest] = tokens

    {country, year, tail_before_year} = locate_year(rest)
    {gi, sem} = gi_of(rest)

    %{
      food_number: num,
      food_item: food_item(lines, pi, i, ni, line, country, tail_before_year),
      category: category,
      country: country,
      year: parse_year(year),
      gi_value: gi,
      gi_sem: sem,
      ref_code: List.last(rest),
      unpublished: unpublished?(List.last(rest)),
      source_table: table
    }
  end

  # Tokens after the number, up to (but excluding) the year, are the inline food name
  # when present; otherwise the name wrapped onto neighbouring lines.
  defp food_item(lines, pi, i, ni, line, country, tail_before_year) do
    inline = tail_before_year |> Enum.join(" ") |> String.trim()

    if inline != "" do
      inline
    else
      wrapped_name(lines, pi, i, ni, cut_col(line, country))
    end
  end

  # A wrapped name spans the left column of the lines just above/below the value line.
  # Bound the claim to the *midpoint* of the gap to each neighbouring value line so a
  # neighbour's name-above / brand-below never leaks in, and drop structural lines
  # (blank / all-caps category / the "Average available carbohydrate" note). Each line
  # is sliced at this row's country column to strip right-column cell wrap.
  defp wrapped_name(lines, pi, i, ni, cut) do
    lo = div(pi + i, 2) + 1
    hi = div(i + ni, 2) - 1

    Enum.reduce(lo..hi//1, [], fn
      ^i, acc ->
        acc

      j, acc ->
        full = lines |> Enum.at(j, "") |> String.trim()
        # Classify structural lines on the *full* text (before slicing off the right
        # column), so a truncated keyword can't sneak a heading/note/furniture line in.
        if full == "" or heading?(full) or note?(full) or furniture?(full) do
          acc
        else
          [lines |> Enum.at(j, "") |> left_of(cut) |> String.trim() | acc]
        end
    end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.trim()
  end

  # ── Column / field helpers ───────────────────────────────────────────────────

  defp split_cols(line) do
    line |> String.trim() |> String.split(~r/\s{2,}/u) |> Enum.reject(&(&1 == ""))
  end

  # Country is the token immediately before the 4-digit year; everything between the
  # number and the country is the inline name (empty when the name wrapped).
  defp locate_year(rest) do
    case Enum.find_index(rest, &Regex.match?(@year, &1)) do
      nil -> {nil, nil, []}
      0 -> {nil, Enum.at(rest, 0), []}
      yi -> {Enum.at(rest, yi - 1), Enum.at(rest, yi), Enum.slice(rest, 0, yi - 1)}
    end
  end

  defp gi_of(rest) do
    Enum.find_value(rest, {nil, nil}, fn tok ->
      case Regex.named_captures(@gi, tok) do
        %{"gi" => gi, "sem" => sem} -> {parse_float(gi), parse_float(sem)}
        _ -> nil
      end
    end)
  end

  defp cut_col(_line, nil), do: 74
  defp cut_col(line, country), do: :binary.match(line, country) |> col_of()

  defp col_of({start, _len}), do: start
  defp col_of(:nomatch), do: 74

  defp left_of(line, cut), do: String.slice(line, 0, cut)

  # ── Category tracking ────────────────────────────────────────────────────────

  # The most recent all-caps section heading in `[from, to)` (or the carried one).
  defp latest_category(lines, from, to, current) do
    from..(to - 1)//1
    |> Enum.reduce(current, fn j, cat ->
      case lines |> Enum.at(j, "") |> String.trim() do
        t -> if Regex.match?(@all_caps, t), do: t, else: cat
      end
    end)
  end

  defp heading?(t), do: Regex.match?(@all_caps, t)

  # The per-category "Average available carbohydrate portion = N g …" note that sits
  # among the entry lines but belongs to no food.
  defp note?(t), do: t =~ ~r/available carbohydrate portion/i

  # Repeated page furniture (running title, author footer, column header, TOC) that
  # can sit between the page edge and the first/last value row. Kept per-page so it
  # only ever competes with edge rows; no real food name contains these.
  @furniture ~r/Supplemental Table|Brand-Miller|Food Number and Item|Online Supplemental|Explanatory note|TABLE OF CONTENTS|: pages? /i
  defp furniture?(t), do: Regex.match?(@furniture, t)

  # ── Parsing primitives ───────────────────────────────────────────────────────

  defp unpublished?(nil), do: false
  defp unpublished?(code), do: String.starts_with?(code, "UO")

  defp parse_year(nil), do: nil
  defp parse_year(y), do: y |> String.trim_trailing("*") |> parse_int()

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  # ── pdftotext shell-out ──────────────────────────────────────────────────────

  defp ensure_pdftotext do
    if System.find_executable("pdftotext"), do: :ok, else: {:error, :pdftotext_missing}
  end

  defp pdftotext(path) do
    case System.cmd("pdftotext", ["-layout", path, "-"], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {err, code} -> {:error, {:pdftotext_failed, code, String.slice(err, 0, 500)}}
    end
  end
end
