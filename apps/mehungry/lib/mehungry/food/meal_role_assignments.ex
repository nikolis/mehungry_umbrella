defmodule Mehungry.Food.MealRoleAssignments do
  @moduledoc """
  Reads and writes the multi-label **meal roles** of recipes
  (`Mehungry.Food.RecipeMealRole`, vocabulary in `Mehungry.Food.MealRoles`).

  Three writers, one rule — **a human decision always wins**:

    * `apply_ai_roles/2` — the classifier's output. Skips any recipe that already
      has a reviewed role; auto-confirms when every role is high-confidence.
    * `set_recipe_roles/3` — an admin's explicit set (add/remove), all reviewed.
    * `confirm_recipe/2`, `confirm_many/2` — an admin accepting the current set.

  Readers: `roles_for/1` (the planner), `list_for_review/2` + `coverage/0` (the
  admin page `/professional/recipe-meal-roles`).

  See `docs/implementation/food/meal_roles.md`.
  """

  import Ecto.Query

  alias Mehungry.Food.{MealRoles, Recipe, RecipeMealRole, RecipeMealRoleRuns}
  alias Mehungry.ObanWorkers.RecipeMealRoleClassificationWorker
  alias Mehungry.Repo

  # A classification whose every role is at least this confident lands already
  # reviewed (same idea as TaxonomyClassificationWorker's auto-confirm).
  @auto_confirm_confidence 0.85

  # Columns the admin list loads — never the (large) embedding vector.
  @list_fields [
    :id,
    :title,
    :description,
    :cousine,
    :servings,
    :nutrients,
    :source,
    :private,
    :image_url,
    :list_image_url,
    :user_id,
    :meal_roles_classified_at,
    :inserted_at
  ]

  # ── reads ──────────────────────────────────────────────────────────────────

  @doc """
  `%{recipe_id => [role]}` for the given recipe ids, roles in vocabulary order.
  Recipes with no roles are absent from the map (treat as unclassified).
  """
  def roles_for([]), do: %{}

  def roles_for(recipe_ids) when is_list(recipe_ids) do
    from(m in RecipeMealRole, where: m.recipe_id in ^recipe_ids, select: {m.recipe_id, m.role})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, roles} -> {id, sort_roles(roles)} end)
  end

  @doc "The role rows of one recipe, in vocabulary order."
  def list_recipe_roles(recipe_id) do
    from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id)
    |> Repo.all()
    |> Enum.sort_by(&role_index(&1.role))
  end

  @doc "True when the recipe has at least one reviewed role."
  def reviewed?(recipe_id) do
    Repo.exists?(from m in RecipeMealRole, where: m.recipe_id == ^recipe_id and m.reviewed)
  end

  @doc """
  Recipes for the admin review list, `meal_roles` + `user` preloaded.

  Filters (all optional):

    * `:status` — `"needs_review"` (default: has an unreviewed role, lowest
      confidence first), `"unclassified"` (no role rows), `"reviewed"` (has
      roles, all reviewed), `"all"`
    * `:role` — has this role
    * `:search` — title contains (case-insensitive)
    * `:source` — `recipes.source` (`"myplate"`, …), or `"in_app"` for nil
    * `:include_private` — include `private` recipes (default false)

  Options: `:limit` (default 25), `:offset`.
  """
  def list_for_review(filters \\ %{}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    status = Map.get(filters, :status, "needs_review")

    from(r in Recipe,
      as: :recipe,
      select: struct(r, ^@list_fields),
      limit: ^limit,
      offset: ^offset
    )
    |> filter_status(status)
    |> filter_role(Map.get(filters, :role))
    |> filter_search(Map.get(filters, :search))
    |> filter_source(Map.get(filters, :source))
    |> filter_private(Map.get(filters, :include_private, false))
    |> order_for(status)
    |> Repo.all()
    |> Repo.preload([:user, meal_roles: from(m in RecipeMealRole, order_by: m.id)])
    |> Enum.map(fn r -> %{r | meal_roles: Enum.sort_by(r.meal_roles, &role_index(&1.role))} end)
  end

  @doc "One recipe shaped like a `list_for_review/2` row (for in-place refreshes)."
  def get_for_review(recipe_id) do
    from(r in Recipe, where: r.id == ^recipe_id, select: struct(r, ^@list_fields))
    |> Repo.one()
    |> case do
      nil ->
        nil

      recipe ->
        recipe = Repo.preload(recipe, [:user, :meal_roles])
        %{recipe | meal_roles: Enum.sort_by(recipe.meal_roles, &role_index(&1.role))}
    end
  end

  defp filter_status(query, "needs_review") do
    where(query, [r], exists(unreviewed_rows()))
  end

  defp filter_status(query, "unclassified") do
    where(query, [r], not exists(any_rows()))
  end

  defp filter_status(query, "reviewed") do
    where(query, [r], exists(any_rows()) and not exists(unreviewed_rows()))
  end

  defp filter_status(query, _all), do: query

  defp any_rows do
    from(m in RecipeMealRole, where: m.recipe_id == parent_as(:recipe).id, select: 1)
  end

  defp unreviewed_rows do
    from(m in RecipeMealRole,
      where: m.recipe_id == parent_as(:recipe).id and not m.reviewed,
      select: 1
    )
  end

  defp filter_role(query, role) when role in [nil, ""], do: query

  defp filter_role(query, role) do
    where(
      query,
      [r],
      exists(
        from(m in RecipeMealRole,
          where: m.recipe_id == parent_as(:recipe).id and m.role == ^role,
          select: 1
        )
      )
    )
  end

  defp filter_search(query, term) when term in [nil, ""], do: query

  defp filter_search(query, term) do
    pattern = "%" <> String.replace(term, ~w(\\ % _), &("\\" <> &1)) <> "%"
    where(query, [r], ilike(r.title, ^pattern))
  end

  defp filter_source(query, source) when source in [nil, ""], do: query
  defp filter_source(query, "in_app"), do: where(query, [r], is_nil(r.source))
  defp filter_source(query, source), do: where(query, [r], r.source == ^source)

  defp filter_private(query, true), do: query
  defp filter_private(query, _), do: where(query, [r], r.private != true or is_nil(r.private))

  defp order_for(query, "needs_review") do
    order_by(query, [r],
      asc:
        fragment(
          "(SELECT MIN(COALESCE(m.confidence, 0)) FROM recipe_meal_roles m WHERE m.recipe_id = ? AND NOT m.reviewed)",
          r.id
        ),
      asc: r.id
    )
  end

  defp order_for(query, _), do: order_by(query, [r], desc: r.id)

  @doc """
  Catalogue coverage for the admin header:
  `%{total, classified, unclassified, reviewed, needs_review, per_role: %{role => n}}`.
  """
  def coverage do
    total = Repo.aggregate(Recipe, :count)

    classified =
      Repo.one(from m in RecipeMealRole, select: count(m.recipe_id, :distinct)) || 0

    needs_review =
      Repo.one(
        from m in RecipeMealRole, where: not m.reviewed, select: count(m.recipe_id, :distinct)
      ) ||
        0

    per_role =
      from(m in RecipeMealRole, group_by: m.role, select: {m.role, count(m.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: total,
      classified: classified,
      unclassified: max(total - classified, 0),
      needs_review: needs_review,
      reviewed: max(classified - needs_review, 0),
      per_role: Map.new(MealRoles.all(), &{&1, Map.get(per_role, &1, 0)})
    }
  end

  # ── writes ─────────────────────────────────────────────────────────────────

  @doc """
  Writes the classifier's roles for one recipe.

  `assignments` is `[%{role: String.t(), confidence: float | nil}]` (unknown
  roles are dropped). Returns:

    * `{:ok, :skipped_reviewed}` — a human already reviewed this recipe; untouched
    * `{:ok, :applied}` — unreviewed AI rows replaced by `assignments`
      (auto-confirmed when every confidence ≥ #{@auto_confirm_confidence})
    * `{:ok, :empty}` — nothing usable; existing rows kept

  Every outcome but `:skipped_reviewed` stamps `meal_roles_classified_at`, so a
  backfill run never re-fetches the same recipe.
  """
  def apply_ai_roles(recipe_id, assignments) do
    assignments =
      assignments
      |> Enum.filter(&MealRoles.valid?(&1.role))
      |> Enum.uniq_by(& &1.role)

    Repo.transaction(fn ->
      cond do
        reviewed?(recipe_id) ->
          :skipped_reviewed

        assignments == [] ->
          stamp_classified(recipe_id)
          :empty

        true ->
          replace_ai_rows(recipe_id, assignments)
          stamp_classified(recipe_id)
          :applied
      end
    end)
  end

  defp replace_ai_rows(recipe_id, assignments) do
    from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id and not m.reviewed)
    |> Repo.delete_all()

    reviewed = auto_confirm?(assignments)

    rows =
      Enum.map(assignments, fn a ->
        row(recipe_id, a.role,
          source: "ai",
          confidence: a[:confidence],
          reviewed: reviewed,
          reviewed_at: if(reviewed, do: now())
        )
      end)

    insert_rows(rows)
  end

  # A `recipe_meal_roles` row map for insert_all.
  defp row(recipe_id, role, attrs) do
    ts = NaiveDateTime.utc_now(:second)

    Map.merge(
      %{
        recipe_id: recipe_id,
        role: role,
        source: "ai",
        confidence: nil,
        reviewed: false,
        reviewed_by_id: nil,
        reviewed_at: nil,
        inserted_at: ts,
        updated_at: ts
      },
      Map.new(attrs)
    )
  end

  defp insert_rows(rows) do
    Repo.insert_all(RecipeMealRole, rows,
      on_conflict: :nothing,
      conflict_target: [:recipe_id, :role]
    )
  end

  defp auto_confirm?(assignments) do
    Enum.all?(assignments, fn a ->
      is_number(a[:confidence]) and a[:confidence] >= @auto_confirm_confidence
    end)
  end

  defp stamp_classified(recipe_id) do
    from(r in Recipe, where: r.id == ^recipe_id)
    |> Repo.update_all(set: [meal_roles_classified_at: now()])
  end

  @doc """
  An admin's explicit role set for a recipe. Roles not in `roles` are removed,
  new ones are added as `source: "manual"`, and every remaining row is marked
  reviewed by `reviewer_id`. Returns `{:ok, [RecipeMealRole]}` or
  `{:error, {:invalid_roles, [role]}}`.
  """
  def set_recipe_roles(recipe_id, roles, reviewer_id) do
    roles = Enum.uniq(roles)

    case Enum.reject(roles, &MealRoles.valid?/1) do
      [] ->
        Repo.transaction(fn -> replace_with_manual(recipe_id, roles, reviewer_id) end)

      invalid ->
        {:error, {:invalid_roles, invalid}}
    end
  end

  defp replace_with_manual(recipe_id, roles, reviewer_id) do
    from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id and m.role not in ^roles)
    |> Repo.delete_all()

    existing =
      from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id, select: m.role)
      |> Repo.all()

    roles
    |> Enum.reject(&(&1 in existing))
    |> Enum.map(
      &row(recipe_id, &1,
        source: "manual",
        reviewed: true,
        reviewed_by_id: reviewer_id,
        reviewed_at: now()
      )
    )
    |> insert_rows()

    mark_reviewed(from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id), reviewer_id)
    stamp_classified(recipe_id)
    list_recipe_roles(recipe_id)
  end

  @doc "Marks a recipe's current roles reviewed. Returns `{:ok, count}`."
  def confirm_recipe(recipe_id, reviewer_id), do: confirm_many([recipe_id], reviewer_id)

  @doc "Marks the current roles of every recipe in `recipe_ids` reviewed."
  def confirm_many(recipe_ids, reviewer_id) when is_list(recipe_ids) do
    {count, _} =
      mark_reviewed(
        from(m in RecipeMealRole, where: m.recipe_id in ^recipe_ids and not m.reviewed),
        reviewer_id
      )

    {:ok, count}
  end

  defp mark_reviewed(query, reviewer_id) do
    Repo.update_all(query,
      set: [
        reviewed: true,
        reviewed_by_id: reviewer_id,
        reviewed_at: now(),
        updated_at: NaiveDateTime.utc_now(:second)
      ]
    )
  end

  # ── classification triggers ────────────────────────────────────────────────

  @doc """
  Recipe ids a classification run of `mode` still has to process, oldest first.

    * `"unclassified"` — never attempted (`meal_roles_classified_at IS NULL`)
    * `"unreviewed"` — no reviewed role and not attempted since `since`
      (the run's start), so a re-classify run always moves forward
  """
  def pending_classification_ids(mode, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    query =
      case mode do
        "unclassified" ->
          from(r in Recipe, as: :recipe, where: is_nil(r.meal_roles_classified_at))

        "unreviewed" ->
          since = Keyword.fetch!(opts, :since)

          from(r in Recipe,
            as: :recipe,
            where:
              not exists(
                from(m in RecipeMealRole,
                  where: m.recipe_id == parent_as(:recipe).id and m.reviewed,
                  select: 1
                )
              ) and
                (is_nil(r.meal_roles_classified_at) or r.meal_roles_classified_at < ^since)
          )
      end

    query = from(r in query, order_by: r.id, select: r.id)
    query = if limit, do: limit(query, ^limit), else: query
    Repo.all(query)
  end

  @doc """
  Starts a tracked backfill run (`"unclassified"` | `"unreviewed"`): opens a
  `RecipeMealRoleRun` and enqueues the first worker batch. Refuses while a run
  is in flight. Returns `{:ok, run}` or `{:error, :already_running}`.
  """
  def enqueue_classification(mode) when mode in ["unclassified", "unreviewed"] do
    if RecipeMealRoleRuns.running?(RecipeMealRoleRuns.latest_run()) do
      {:error, :already_running}
    else
      started = now()
      total = length(pending_classification_ids(mode, since: started))
      run = RecipeMealRoleRuns.start_run(mode, total)

      {:ok, _job} =
        %{"run_id" => run.id, "mode" => mode, "since" => DateTime.to_iso8601(run.started_at)}
        |> RecipeMealRoleClassificationWorker.new()
        |> Oban.insert()

      {:ok, run}
    end
  end

  @doc """
  (Re)classifies one recipe in the background, even if already classified. A
  recipe with a reviewed role is still left alone by `apply_ai_roles/2`; the
  admin "Reclassify" button goes through `reset_and_classify/1` instead.
  """
  def classify_recipe_now(recipe_id) do
    RecipeMealRoleClassificationWorker.enqueue_recipe(recipe_id)
  end

  @doc """
  Admin "Reclassify": deletes every role row of the recipe (reviewed or not —
  the admin explicitly asked for a fresh opinion) and enqueues a classification.
  """
  def reset_and_classify(recipe_id) do
    from(m in RecipeMealRole, where: m.recipe_id == ^recipe_id) |> Repo.delete_all()
    classify_recipe_now(recipe_id)
  end

  @doc """
  The save hook: called after every recipe create/update. Enqueues a
  classification unless a human already reviewed the recipe's roles.
  """
  def maybe_classify_on_save(recipe_id) do
    if reviewed?(recipe_id), do: :skipped, else: classify_recipe_now(recipe_id)
  end

  # ── classifier input ───────────────────────────────────────────────────────

  @doc """
  Builds the classifier's per-recipe input maps for `recipe_ids`: title,
  description (truncated), cuisine, servings, up to 12 ingredient names,
  per-serving kcal + protein (via the calendar's `NutrientUtils.macro_summary/1`)
  and total time.
  """
  def classifier_inputs(recipe_ids) do
    from(r in Recipe,
      where: r.id in ^recipe_ids,
      select:
        struct(r, [
          :id,
          :title,
          :description,
          :cousine,
          :servings,
          :nutrients,
          :cooking_time_upper_limit,
          :preperation_time_upper_limit
        ]),
      order_by: r.id
    )
    |> Repo.all()
    |> Repo.preload(recipe_ingredients: :ingredient)
    |> Enum.map(&classifier_input/1)
  end

  defp classifier_input(recipe) do
    {kcal, protein} = per_serving_macros(recipe)

    %{
      id: recipe.id,
      title: recipe.title,
      description: truncate(recipe.description, 300),
      cuisine: recipe.cousine,
      servings: recipe.servings,
      ingredients:
        recipe.recipe_ingredients
        |> Enum.map(&(&1.ingredient && &1.ingredient.name))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.take(12),
      kcal_per_serving: kcal,
      protein_g_per_serving: protein,
      total_time_min:
        (recipe.cooking_time_upper_limit || 0) + (recipe.preperation_time_upper_limit || 0)
    }
  end

  @doc """
  `{kcal, protein_g}` per serving from a recipe's stored `nutrients` (both nil
  when there's no nutrition data). Shared by the classifier and the admin list.
  """
  def per_serving_macros(%{nutrients: nutrients} = recipe)
      when is_map(nutrients) and map_size(nutrients) > 0 do
    summary = Mehungry.NutrientUtils.macro_summary(nutrients)

    servings =
      if is_integer(recipe.servings) and recipe.servings > 0, do: recipe.servings, else: 1

    kcal = if summary.energy_kcal > 0, do: round(summary.energy_kcal / servings)
    protein = if summary.protein_g > 0, do: Float.round(summary.protein_g / servings, 1)
    {kcal, protein}
  rescue
    _ -> {nil, nil}
  end

  def per_serving_macros(_), do: {nil, nil}

  # ── helpers ────────────────────────────────────────────────────────────────

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "…"

  defp sort_roles(roles), do: Enum.sort_by(roles, &role_index/1)

  defp role_index(role), do: Enum.find_index(MealRoles.all(), &(&1 == role)) || 99

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
