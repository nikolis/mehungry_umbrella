defmodule Mehungry.Food.ParsedFoods do
  @moduledoc """
  Structured parses of USDA ingredient descriptions — the persistence and
  review layer over `Mehungry.FoodData.Usda.Parser.Pipeline`.

  Mirrors `Mehungry.Food.IdentityResolution`'s guarantees:

    * **Never overwrites.** Writes are find-or-create on
      `(ingredient_id, parser_version)`; the parser is deterministic, so a
      same-version re-run is a no-op.
    * **Preserves history.** Verifying a parse marks any previously verified
      one `superseded` (chained via `superseded_by_id`), never deletes it.
    * **Manual review workflow** — candidates may be edited
      (`update_parsed_candidate/2`) and then verified or rejected; verifying
      links (find-or-creating) the `CanonicalFood` lexicon row, so the
      lexicon grows through review.

  Bulk parsing is driven by `Mehungry.ObanWorkers.IngredientFoodParsingWorker`
  with progress tracked in `FoodParsingRuns`. Scope is fdc-backed ingredients
  only — only USDA descriptions follow the "Primary, qualifier" grammar.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    FoodParsingRuns,
    Ingredient,
    IngredientParsedFood,
    ParserVocabulary
  }

  alias Mehungry.FoodData.Usda.Parser.{Pipeline, Result, Skipped, Vocabulary}

  # ── Parsing (never-overwrite writes) ─────────────────────────────────────

  @doc """
  Parses one ingredient's description and stores the outcome (parse or skip)
  as a candidate row at the current parser version. Find-or-create — an
  existing row for `(ingredient, version)` is returned untouched.
  """
  def parse_ingredient(%Ingredient{} = ingredient) do
    ingredient.name
    |> Pipeline.parse(trace: true)
    |> to_attrs(ingredient)
    |> add_parsed_candidate()
  end

  @doc """
  Find-or-create a parsed-food row on the natural key
  `(ingredient_id, parser_version)`. Returns `{:ok, parsed, :created | :exists}`.
  """
  def add_parsed_candidate(attrs) do
    attrs = Map.new(attrs)

    case get_by_natural_key(attrs) do
      %IngredientParsedFood{} = existing ->
        {:ok, existing, :exists}

      nil ->
        case %IngredientParsedFood{}
             |> IngredientParsedFood.changeset(attrs)
             |> Repo.insert() do
          {:ok, parsed} ->
            {:ok, parsed, :created}

          # Lost an insert race on the unique index — fetch the winner.
          {:error, _changeset} ->
            {:ok, get_by_natural_key(attrs), :exists}
        end
    end
  end

  def get_parsed_food!(id) do
    IngredientParsedFood |> Repo.get!(id) |> Repo.preload(:ingredient)
  end

  # ── Review workflow ──────────────────────────────────────────────────────

  @editable_fields ~w(canonical_food_text harvest_stage processing processing_modifiers packaging part dismemberment bone_state portion grade fat notes)

  @doc """
  Admin edit of a parse before verification. Only rows still in `candidate`
  status are editable, and only the semantic fields (#{Enum.join(@editable_fields, ", ")}).
  """
  def update_parsed_candidate(id, attrs) do
    parsed = Repo.get!(IngredientParsedFood, id)

    if parsed.status == "candidate" do
      parsed
      |> IngredientParsedFood.changeset(edit_attrs(attrs))
      |> Repo.update()
    else
      {:error, :not_editable}
    end
  end

  @doc """
  Marks a parse `verified`. Any parse currently `verified` for the same
  ingredient is first marked `superseded` and pointed at the newly-verified
  one. The (possibly admin-edited) `canonical_food_text` is linked to the
  lexicon — find-or-creating the `CanonicalFood` row — inside the same
  transaction; the vocabulary cache is reloaded after commit.
  """
  def verify_parsed_food(id, user_id \\ nil) do
    result =
      Repo.transaction(fn ->
        parsed = Repo.get!(IngredientParsedFood, id)

        if parsed.skip_reason, do: Repo.rollback(:skipped_row)

        from(p in IngredientParsedFood,
          where:
            p.ingredient_id == ^parsed.ingredient_id and p.status == "verified" and p.id != ^id
        )
        |> Repo.update_all(set: [status: "superseded", superseded_by_id: id, updated_at: now()])

        {:ok, food} = ParserVocabulary.get_or_create_canonical_food(parsed.canonical_food_text)

        {:ok, verified} =
          parsed
          |> IngredientParsedFood.changeset(%{
            status: "verified",
            canonical_food_id: food.id,
            verified_by_user_id: user_id,
            verified_at: now()
          })
          |> Repo.update()

        verified
      end)

    with {:ok, _verified} <- result, do: Vocabulary.reload()
    result
  end

  @doc "Marks a parse `rejected` (kept for history)."
  def reject_parsed_food(id, _user_id \\ nil) do
    IngredientParsedFood
    |> Repo.get!(id)
    |> IngredientParsedFood.changeset(%{status: "rejected"})
    |> Repo.update()
  end

  @doc """
  Unreviewed (candidate) parses at the current parser version,
  lowest-confidence first, ingredient preloaded.
  """
  def list_pending_parse_review(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(p in IngredientParsedFood,
        where:
          p.status == "candidate" and is_nil(p.skip_reason) and
            p.parser_version == ^Pipeline.version(),
        order_by: [asc_nulls_first: p.confidence, asc: p.id],
        preload: [:ingredient],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  @doc """
  Skipped descriptions (`skip_reason` set) at the current parser version —
  read-only review, newest first, ingredient preloaded.
  """
  def list_skipped_parses(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(p in IngredientParsedFood,
        where: not is_nil(p.skip_reason) and p.parser_version == ^Pipeline.version(),
        order_by: [desc: p.id],
        preload: [:ingredient],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  # ── Progress + batching ──────────────────────────────────────────────────

  @doc """
  Coverage snapshot `%{processed: n, total: m}` for the progress bar, computed
  from the stored rows at the current parser version (accurate without live
  broadcasts).
  """
  def parsing_progress do
    total = Repo.aggregate(fdc_backed(), :count)

    processed =
      from(p in IngredientParsedFood,
        join: i in subquery(fdc_backed()),
        on: i.id == p.ingredient_id,
        where: p.parser_version == ^Pipeline.version(),
        select: count(p.ingredient_id, :distinct)
      )
      |> Repo.one()

    %{processed: processed, total: total}
  end

  @doc "A batch of fdc-backed ingredients without a parse at the current version."
  def list_unparsed_ingredients(limit) do
    Repo.all(
      from(i in Ingredient,
        left_join: p in IngredientParsedFood,
        on: p.ingredient_id == i.id and p.parser_version == ^Pipeline.version(),
        where: not is_nil(i.fdc_id) and i.fdc_id > 0 and is_nil(p.id),
        order_by: [desc: i.id],
        limit: ^limit
      )
    )
  end

  @doc "Opens a tracked run and enqueues the first parsing batch."
  def enqueue_food_parsing do
    run = FoodParsingRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.IngredientFoodParsingWorker.new()
      |> Oban.insert()

    {:ok, run}
  end

  # ── internals ────────────────────────────────────────────────────────────

  defp fdc_backed do
    from(i in Ingredient, where: not is_nil(i.fdc_id) and i.fdc_id > 0)
  end

  defp get_by_natural_key(attrs) do
    Repo.get_by(IngredientParsedFood,
      ingredient_id: attrs[:ingredient_id] || attrs["ingredient_id"],
      parser_version: attrs[:parser_version] || attrs["parser_version"]
    )
  end

  defp to_attrs({:ok, %Result{} = result}, %Ingredient{id: ingredient_id}) do
    %{
      ingredient_id: ingredient_id,
      canonical_food_id: result.canonical_food_id,
      canonical_food_text: result.canonical_food,
      harvest_stage: Atom.to_string(result.harvest_stage),
      processing: Enum.map(result.processing, &Atom.to_string/1),
      processing_modifiers: result.processing_modifiers,
      packaging: Atom.to_string(result.packaging),
      part: result.part,
      dismemberment: result.dismemberment,
      bone_state: result.bone_state,
      portion: result.portion,
      grade: result.grade,
      fat: result.fat,
      confidence: result.confidence,
      parser_version: Pipeline.version(),
      trace: normalize_trace(result.trace),
      status: "candidate"
    }
  end

  defp to_attrs({:skipped, %Skipped{} = skipped}, %Ingredient{id: ingredient_id}) do
    %{
      ingredient_id: ingredient_id,
      skip_reason: Atom.to_string(skipped.reason),
      confidence: skipped.confidence,
      parser_version: Pipeline.version(),
      trace: normalize_trace(skipped.trace),
      status: "candidate"
    }
  end

  # Trace entries carry atoms and module names; make them JSON-friendly for
  # the jsonb column.
  defp normalize_trace(nil), do: nil
  defp normalize_trace(trace), do: Enum.map(trace, &json_safe/1)

  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(nil), do: nil

  defp json_safe(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {json_safe(k), json_safe(v)} end)

  defp json_safe(value), do: inspect(value)

  defp edit_attrs(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.take(@editable_fields)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
