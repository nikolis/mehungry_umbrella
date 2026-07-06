defmodule Mehungry.SqlUtils do
  @moduledoc """
  Ad-hoc query diagnostics.

  Lets you take a raw SQL string (as copied out of a `[SlowQuery]` log
  line, for example) and run `EXPLAIN ANALYZE` on it directly from
  `iex -S mix phx.server`, without hand-editing the query.

      iex> Mehungry.SqlUtils.explain_analyze("select * from recipes where user_id = $1", [123])
      Aggregate  (cost=1.23..1.24 rows=1 width=8) (actual time=0.045..0.045 rows=1 loops=1)
        ->  Index Scan using recipes_user_id_index on recipes ...
      Planning Time: 0.123 ms
      Execution Time: 0.456 ms
      :ok

  `explain_analyze/3` accepts `format: :map` if you want the parsed JSON
  plan back as data (e.g. to pull out `"Execution Time"`) instead of a
  printed string.

  For a multi-line query, use a heredoc — but remember the opening
  `\"""` must be followed immediately by a newline, nothing else on
  that line:

      iex> Mehungry.SqlUtils.explain_analyze(\"""
      ...> SELECT r0."id", r0."title"
      ...> FROM "recipes" AS r0
      ...> WHERE r0."user_id" = $1
      ...> \""", [1])
      Index Scan using recipes_user_id_index on recipes r0  (cost=0.14..4.25 rows=1 width=27) (actual time=0.006..0.007 rows=0 loops=1)
        Index Cond: (user_id = '1'::bigint)
        Buffers: shared hit=1
      Planning:
        Buffers: shared hit=126
      Planning Time: 1.193 ms
      Execution Time: 0.036 ms
      :ok

  Writing `explain_analyze(\"""SELECT ...` with the query starting on
  the same line as the opening `\"""` is invalid Elixir syntax and
  raises `SyntaxError: heredoc allows only whitespace characters
  followed by a new line after opening \"""`. Use a plain string
  (single or double quoted, escaping embedded `"`) or `~s(...)` instead
  if you want the query on one line.
  """

  alias Mehungry.Repo

  @type sql :: String.t()
  @type params :: list()

  @doc """
  Runs `EXPLAIN` for `query` and prints the plan to stdout.

  `params` are positional query params (`$1`, `$2`, ...), passed straight
  through to `Repo.query/3` — the query itself is never modified other
  than wrapping it in an `EXPLAIN (...)` clause, so it's safe to hand it
  arbitrary read (or write) SQL copied from a log line.

  Options:
    * `:analyze` - adds `ANALYZE` to the explain options, which actually
      executes the query to get real timings/row counts (as opposed to
      just the planner's estimate). Defaults to `true`. Set to `false`
      for queries with side effects you don't want to run for real, or
      when you only care about the planner's estimate.
    * `:buffers` - adds `BUFFERS`, showing buffer/cache usage. Defaults
      to the value of `:analyze` (buffers only make sense alongside a
      real run).
    * `:format` - `:text` (default, prints the human-readable plan and
      returns `:ok`) or `:map` (returns the parsed JSON plan without
      printing anything).

  Returns `:ok` for `:text`, or the plan (a map) for `:map`.
  """
  @spec explain_analyze(sql(), params(), keyword()) :: :ok | map()
  def explain_analyze(query, params \\ [], opts \\ []) do
    analyze? = Keyword.get(opts, :analyze, true)
    buffers? = Keyword.get(opts, :buffers, analyze?)
    format = Keyword.get(opts, :format, :text)

    explain_opts =
      [{"ANALYZE", analyze?}, {"BUFFERS", buffers?}, {"FORMAT", explain_format(format)}]
      |> Enum.filter(fn {_flag, enabled?} -> enabled? end)
      |> Enum.map(fn
        {"FORMAT", value} -> "FORMAT #{value}"
        {flag, true} -> flag
      end)
      |> Enum.join(", ")

    explain_sql = "EXPLAIN (#{explain_opts}) #{query}"

    case Repo.query(explain_sql, params) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        render_result(rows, format)

      {:error, error} ->
        raise error
    end
  end

  defp explain_format(:map), do: "JSON"
  defp explain_format(_text), do: "TEXT"

  defp render_result(rows, :map) do
    rows |> List.flatten() |> List.first()
  end

  defp render_result(rows, :text) do
    rows
    |> List.flatten()
    |> Enum.each(&IO.puts/1)

    :ok
  end
end
