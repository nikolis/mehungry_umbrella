defmodule Mehungry.Health do
  @moduledoc """
  Health Recommendation Knowledge — a registry of health conditions and the
  dietary recommendations linking them to bioactive compounds.

  A `Condition` (Kidney Stones, IBS, Gout, …) is a shared reference entity;
  `CompoundRecommendation` links a condition to a `Mehungry.Food.Compound` as
  advice (e.g. *Kidney Stones: avoid Oxalate*, *IBS: limit FODMAP*).

  This is the **advice** layer that the "facts only" compound stack
  (`docs/science/food_compounds.md` §4) deliberately defers to. Its hard rule: a condition
  references a **compound**, never a species or ingredient. "Which foods should a
  kidney-stone patient avoid?" is answered by `species_for_condition/2` (the primary
  read), which **composes** this layer with `Food.SpeciesCompoundRelationship` at read
  time; `ingredients_for_condition/2` derives the ingredients strictly through those
  species. The schemas themselves stay decoupled from food data.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Compound,
    CompoundTranslation,
    FoundementalFood,
    FoundementalFoodSpeciesTranslation,
    IngredientNutrient,
    Recipe,
    RecipeIngredient,
    SpeciesCompoundRelationship,
    SpeciesCompoundRelationshipStudy
  }

  alias Mehungry.Health.{
    Condition,
    ConditionState,
    ConditionStateRecommendation,
    ConditionStateRecommendationStudy,
    CompoundRecommendation,
    CompoundRecommendationStudy,
    ConditionIdentifier,
    ConditionTranslation,
    NutrientRecommendation,
    NutrientTargets
  }

  alias Mehungry.Literature.ScientificStudy

  alias Mehungry.Languages.Locale

  # Read-through cache for the editorial, shared-safe condition-page reads. These
  # rows are curated (at /professional/health) and vary only by entity id + language,
  # so a shared cache is safe; a moderate TTL lets admin edits surface without
  # having to bust every write path. Namespaced tuple keys mirror Recipes.get_recipe!/1.
  @cache_key_ns Mehungry.Health
  @cache_ttl :timer.hours(1)

  # Curation is rare (admin-only) and every cached read (`get_condition/2`,
  # `recommendations_for_condition/2`, `species_for_condition/3`) is keyed on a
  # condition id fanned across language/recommendation variants, so any write to
  # the condition/recommendation tables clears the whole cache rather than trying
  # to enumerate those variants. Without this the read-through cache serves the
  # pre-write snapshot for up to @cache_ttl.
  defp bust_cache do
    Cachex.clear(:health_cache)
    :ok
  end

  # ── Condition registry ────────────────────────────────────────────────────

  def create_condition(attrs) do
    %Condition{}
    |> Condition.changeset(attrs)
    |> Repo.insert()
    |> tap_ok()
  end

  # Bust the cache after a successful write; pass other results through untouched.
  defp tap_ok({:ok, _} = result) do
    bust_cache()
    result
  end

  defp tap_ok(result), do: result

  @doc "A changeset for a condition — for admin forms."
  def change_condition(condition \\ %Condition{}, attrs \\ %{}) do
    Condition.changeset(condition, attrs)
  end

  @doc "Delete a condition by id; its `compound_recommendations` cascade (`on_delete`)."
  def delete_condition(id) do
    case Repo.get(Condition, id) do
      nil -> {:error, :not_found}
      condition -> condition |> Repo.delete() |> tap_ok()
    end
  end

  @doc "Find-or-create a condition by its natural key `name`, backed by the unique index."
  def upsert_condition(attrs) do
    attrs
    |> create_condition()
    |> case do
      {:ok, condition} ->
        {:ok, condition}

      {:error, _changeset} ->
        name = attrs[:name] || attrs["name"]
        {:ok, Repo.one!(from(c in Condition, where: c.name == ^name))}
    end
  end

  def get_condition!(id), do: Repo.get!(Condition, id)

  @doc """
  Fetch a condition by id, or `nil` if it does not exist. Pass a `language`
  (ISO locale, e.g. `"el"`) to overlay its `condition_translations` name/description
  (per-field fallback to the base record); `nil`/`"en"` returns the base record.
  """
  def get_condition(id, language \\ nil) do
    key = {@cache_key_ns, {:condition, id, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        case Repo.get(Condition, id) do
          nil ->
            nil

          condition ->
            localized = localize_condition(condition, language)
            Cachex.put(:health_cache, key, localized, ttl: @cache_ttl)
            localized
        end

      {:ok, cached} ->
        cached
    end
  end

  def get_condition_by_name(name), do: Repo.get_by(Condition, name: name)

  def list_conditions, do: Repo.all(from(c in Condition, order_by: [asc: c.name]))

  def list_conditions_for_presentation(language \\ nil) do
    query =
      from c in Condition,
        as: :condition,
        where:
          exists(
            from cr in CompoundRecommendation,
              where: cr.condition_id == parent_as(:condition).id
          ) or
            exists(
              from nr in NutrientRecommendation,
                where: nr.condition_id == parent_as(:condition).id
            )

    query
    |> Repo.all()
    |> localize_conditions(language)
  end

  def list_conditions_by_category(category) do
    Repo.all(
      from(c in Condition,
        where: c.category == ^category,
        order_by: [asc: c.name]
      )
    )
  end

  # ── Condition states / phases (Active Flare vs Remission …) ───────────────
  # A per-condition disease-state registry. Advice can be tagged with a state; a
  # `nil` state is general / all-phase. Most conditions carry no states.

  @doc "Ordered states (phases) for a condition, or `[]` if it has none."
  def list_states_for_condition(condition_id) do
    Repo.all(
      from(s in ConditionState,
        where: s.condition_id == ^condition_id,
        order_by: [asc: s.position, asc: s.name]
      )
    )
  end

  @doc "The condition's default state (the phase shown when none is picked), or `nil`."
  def get_default_state(condition_id) do
    Repo.one(
      from(s in ConditionState,
        where: s.condition_id == ^condition_id and s.is_default == true,
        order_by: [asc: s.position],
        limit: 1
      )
    )
  end

  def get_condition_state!(id), do: Repo.get!(ConditionState, id)

  @doc "A changeset for a condition state — for admin forms."
  def change_condition_state(state \\ %ConditionState{}, attrs \\ %{}) do
    ConditionState.changeset(state, attrs)
  end

  @doc "Find-or-create/refresh a condition state by its natural key `(condition_id, slug)`."
  def upsert_state(attrs) do
    %ConditionState{}
    |> ConditionState.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:name, :is_default, :position, :description, :updated_at]},
      conflict_target: [:condition_id, :slug]
    )
    |> tap_ok()
  end

  def delete_state(%ConditionState{} = state), do: state |> Repo.delete() |> tap_ok()

  def delete_state(id) do
    case Repo.get(ConditionState, id) do
      nil -> {:error, :not_found}
      state -> delete_state(state)
    end
  end

  # ── Phase-aware (state-tagged) recommendations — DECOUPLED store ───────────
  # A separate advice store surfaced only on the condition page's phase selector, so
  # phase-specific advice never leaks into the shared read seams (/foods, badges,
  # blueprint) until the "combine" step. `condition_state_id = nil` is general.

  @doc """
  Phase-aware recommendations for a condition. With `state_id`, returns the rows for
  that state **plus** the general (`nil`) rows (general advice applies across phases);
  with `nil`, only the general rows. `:compound`, `:condition_state` and frozen
  `:studies` preloaded. Cached (state is part of the key).
  """
  def state_recommendations_for_condition(condition_id, state_id \\ nil, language \\ nil) do
    key = {@cache_key_ns, {:state_recs, condition_id, state_id, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        rows =
          Repo.all(state_recommendations_query(condition_id, state_id))
          |> Repo.preload([:compound, :condition_state, :studies])
          |> localize_state_recommendations(language)

        Cachex.put(:health_cache, key, rows, ttl: @cache_ttl)
        rows

      {:ok, cached} ->
        cached
    end
  end

  defp state_recommendations_query(condition_id, nil) do
    from(r in ConditionStateRecommendation,
      where: r.condition_id == ^condition_id and is_nil(r.condition_state_id),
      order_by: [asc: r.recommendation, asc: r.id]
    )
  end

  defp state_recommendations_query(condition_id, state_id) do
    from(r in ConditionStateRecommendation,
      where:
        r.condition_id == ^condition_id and
          (r.condition_state_id == ^state_id or is_nil(r.condition_state_id)),
      order_by: [asc: r.recommendation, asc: r.id]
    )
  end

  # Overlay the compound's localized name where present (nutrient/pattern rows pass through).
  defp localize_state_recommendations(rows, nil), do: rows

  defp localize_state_recommendations(rows, _language), do: rows

  @doc "Every phase-aware recommendation for a condition (all states) — for the admin view."
  def list_all_state_recommendations_for_condition(condition_id) do
    Repo.all(
      from(r in ConditionStateRecommendation,
        where: r.condition_id == ^condition_id,
        order_by: [asc: r.condition_state_id, asc: r.recommendation, asc: r.id],
        preload: [:compound, :condition_state, :studies]
      )
    )
  end

  @doc "A changeset for a phase-aware recommendation — for admin forms."
  def change_state_recommendation(rec \\ %ConditionStateRecommendation{}, attrs \\ %{}) do
    ConditionStateRecommendation.changeset(rec, put_state_dedup_key(attrs))
  end

  @doc """
  Upsert a phase-aware recommendation, idempotent on its computed `dedup_key`
  (one row per condition/state/target/source). Used by candidate promotion and the
  hand-authoring form.
  """
  def upsert_state_recommendation(attrs) do
    attrs = put_state_dedup_key(attrs)

    %ConditionStateRecommendation{}
    |> ConditionStateRecommendation.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace, [:recommendation, :severity, :evidence_level, :notes, :source_reference, :updated_at]},
      conflict_target: [:dedup_key],
      returning: true
    )
    |> tap_ok()
  end

  def delete_state_recommendation(%ConditionStateRecommendation{} = rec) do
    rec |> Repo.delete() |> tap_ok()
  end

  def delete_state_recommendation(id) do
    case Repo.get(ConditionStateRecommendation, id) do
      nil -> {:error, :not_found}
      rec -> delete_state_recommendation(rec)
    end
  end

  # Compute the deterministic dedup key (target column is nullable, so a single stable
  # string replaces a composite unique index — see the candidate table). Normalizes to
  # string keys so the changeset's cast sees a consistent map.
  defp put_state_dedup_key(attrs) do
    m = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    target =
      cond do
        m["compound_id"] -> "c#{m["compound_id"]}"
        present_str(m["nutrient_name"]) -> "n#{norm_str(m["nutrient_name"])}"
        true -> "r#{norm_str(m["raw_food_term"])}"
      end

    Map.put(m, "dedup_key", "#{m["condition_id"]}|#{m["condition_state_id"] || 0}|#{target}|#{m["source"] || "manual"}")
  end

  defp present_str(v), do: is_binary(v) and v != ""
  defp norm_str(nil), do: ""
  defp norm_str(v), do: v |> to_string() |> String.trim() |> String.downcase()

  # ── Condition cross-database identifiers (mesh/icd…) ──────────────────────
  # Mirror of the `Food.Compounds` identifier API — the disease-resolution seam.

  @doc "Fetch the condition owning `(namespace, identifier)`, or nil."
  def get_condition_by_identifier(namespace, identifier) do
    Repo.one(
      from(c in Condition,
        join: i in ConditionIdentifier,
        on: i.condition_id == c.id,
        where: i.namespace == ^namespace and i.identifier == ^identifier
      )
    )
  end

  @doc "Insert-or-update a condition identifier, keyed on `(namespace, identifier)`."
  def upsert_condition_identifier(attrs) do
    %ConditionIdentifier{}
    |> ConditionIdentifier.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:condition_id, :is_primary, :source, :updated_at]},
      conflict_target: [:namespace, :identifier]
    )
  end

  def list_condition_identifiers(condition_id) do
    Repo.all(from(i in ConditionIdentifier, where: i.condition_id == ^condition_id))
  end

  # ── Condition ↔ compound recommendations (dietary advice) ─────────────────

  def create_recommendation(attrs) do
    %CompoundRecommendation{}
    |> CompoundRecommendation.changeset(attrs)
    |> Repo.insert()
    |> tap_ok()
  end

  @doc """
  Insert or update a recommendation, keyed on `(condition_id, compound_id, source)`.
  Re-asserting from the same source overwrites (a correction); a different source is
  kept as a distinct row.
  """
  def upsert_recommendation(attrs) do
    %CompoundRecommendation{}
    |> CompoundRecommendation.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:condition_id, :compound_id, :source]
    )
    |> tap_ok()
  end

  def delete_recommendation(%CompoundRecommendation{} = recommendation),
    do: recommendation |> Repo.delete() |> tap_ok()

  def get_recommendation!(id), do: Repo.get!(CompoundRecommendation, id)

  @doc """
  The recommendation rows for a condition, each with its `:compound` preloaded.
  Pass a `language` to overlay the compound's `compound_translations` name.
  """
  def recommendations_for_condition(condition_id, language \\ nil) do
    key = {@cache_key_ns, {:recommendations, condition_id, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        result = do_recommendations_for_condition(condition_id, language)
        Cachex.put(:health_cache, key, result, ttl: @cache_ttl)
        result

      {:ok, cached} ->
        cached
    end
  end

  defp do_recommendations_for_condition(condition_id, language) do
    Repo.all(
      from(r in CompoundRecommendation,
        join: c in Compound,
        on: c.id == r.compound_id,
        where: r.condition_id == ^condition_id,
        order_by: [asc: c.name],
        preload: [compound: c, studies: ^studies_newest_first()]
      )
    )
    |> localize_recommendation_compounds(language)
  end

  @doc """
  The recommendation rows for a compound, each with its `:condition` and frozen
  reference `:studies` (PubMed provenance) preloaded.
  """
  def recommendations_for_compound(compound_id) do
    Repo.all(
      from(r in CompoundRecommendation,
        join: c in Condition,
        on: c.id == r.condition_id,
        where: r.compound_id == ^compound_id,
        order_by: [asc: c.name],
        preload: [condition: c, studies: ^studies_newest_first()]
      )
    )
  end

  # Newest-first ordering for a recommendation/fact's frozen reference studies.
  defp studies_newest_first, do: from(s in ScientificStudy, order_by: [desc: s.id])

  @doc """
  Upsert a condition and link it to an existing compound in one call — the
  "Kidney Stones: avoid Oxalate" convenience. `rec_attrs` supplies
  `recommendation`, `severity`, `evidence_level`, `source`, `notes`;
  `condition_id`/`compound_id` are injected. Mirrors
  `Mehungry.Food.add_compound_to_ingredient/3`.
  """
  def add_recommendation(condition_id, compound_id, rec_attrs)
      when is_integer(condition_id) do
    rec_attrs
    |> Map.new()
    |> Map.merge(%{condition_id: condition_id, compound_id: compound_id})
    |> upsert_recommendation()
  end

  def add_recommendation(condition_attrs, compound_id, rec_attrs) do
    with {:ok, condition} <- upsert_condition(condition_attrs) do
      add_recommendation(condition.id, compound_id, rec_attrs)
    end
  end

  # ── Derived cross-layer read (composition, not schema coupling) ───────────

  @doc """
  The **food species** implicated for a condition, composing this advice layer with
  the species-facts layer at **read time**: `condition → compound_recommendations →
  compounds → species_compound_relationships → species`.

  Conditions never reference species (or ingredients) directly — this join resolves
  the food through the shared compound. Pass a `recommendation` (e.g. `"avoid"` /
  `:avoid`) to filter, or `nil`/omit for every recommendation. Returns maps of
  `%{species, compound, recommendation, severity, evidence_level}` so a caller can
  render "avoid Spinach (high Oxalate)".
  """
  def species_for_condition(condition_id, recommendation \\ nil, language \\ nil) do
    key = {@cache_key_ns, {:species, condition_id, recommendation, language}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        result = do_species_for_condition(condition_id, recommendation, language)
        Cachex.put(:health_cache, key, result, ttl: @cache_ttl)
        result

      {:ok, cached} ->
        cached
    end
  end

  defp do_species_for_condition(condition_id, recommendation, language) do
    from(rec in CompoundRecommendation,
      join: scr in SpeciesCompoundRelationship,
      on: scr.compound_id == rec.compound_id,
      join: cmp in Compound,
      on: cmp.id == rec.compound_id,
      join: sp in assoc(scr, :species),
      where: rec.condition_id == ^condition_id,
      # Defense-in-depth: a compound curated `non_dietary` (assay reagent, solvent,
      # contaminant, non-specific class) must never drive advice, even if a stray
      # fact/recommendation exists for it.
      where: cmp.dietary_relevance != "non_dietary",
      order_by: [asc: sp.name, asc: cmp.name],
      select: %{
        species: sp,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity,
        evidence_level: rec.evidence_level,
        recommendation_id: rec.id,
        relationship_id: scr.id
      }
    )
    |> maybe_filter_recommendation(recommendation)
    |> Repo.all()
    |> attach_species_citations()
    |> localize_species_rows(language)
  end

  # Attach frozen PubMed provenance to each species advice row — the full "why this
  # food" chain: `:recommendation_citations` (the condition↔compound advice's studies)
  # and `:fact_citations` (the species↔compound fact's studies). Batch-loaded to avoid
  # N+1; each is a (possibly empty) list of `ScientificStudy` structs.
  defp attach_species_citations(rows) do
    rec_ids = rows |> Enum.map(& &1.recommendation_id) |> Enum.uniq()
    rel_ids = rows |> Enum.map(& &1.relationship_id) |> Enum.uniq()

    rec_studies =
      studies_by_parent(
        CompoundRecommendationStudy,
        :recommendation_id,
        rec_ids
      )

    fact_studies =
      studies_by_parent(
        SpeciesCompoundRelationshipStudy,
        :relationship_id,
        rel_ids
      )

    Enum.map(rows, fn row ->
      row
      |> Map.put(:recommendation_citations, Map.get(rec_studies, row.recommendation_id, []))
      |> Map.put(:fact_citations, Map.get(fact_studies, row.relationship_id, []))
    end)
  end

  # `%{parent_id => [ScientificStudy, ...]}` for a result↔study join table, newest
  # study first.
  defp studies_by_parent(_join, _fk, []), do: %{}

  defp studies_by_parent(join_schema, fk, parent_ids) do
    from(j in join_schema,
      join: s in ScientificStudy,
      on: s.id == j.study_id,
      where: field(j, ^fk) in ^parent_ids,
      order_by: [desc: s.id],
      select: {field(j, ^fk), s}
    )
    |> Repo.all()
    |> Enum.group_by(fn {parent_id, _s} -> parent_id end, fn {_id, s} -> s end)
  end

  @doc """
  The dietary advice implicated for a **food species** — the inverse of
  `species_for_condition/2`: `species → species_compound_relationships → compounds →
  compound_recommendations → conditions`. Returns maps of
  `%{compound, condition, recommendation, severity, evidence_level, source}` so a
  species page can render "Oxalate — avoid for Kidney Stones (high)". Ordered by
  condition then compound.
  """
  def recommendations_for_species(species_id) do
    Repo.all(
      from(scr in SpeciesCompoundRelationship,
        join: rec in CompoundRecommendation,
        on: rec.compound_id == scr.compound_id,
        join: cmp in Compound,
        on: cmp.id == scr.compound_id,
        join: cond in Condition,
        on: cond.id == rec.condition_id,
        where: scr.foundemental_species_id == ^species_id,
        # A `non_dietary` compound must never drive advice (see species_for_condition).
        where: cmp.dietary_relevance != "non_dietary",
        order_by: [asc: cond.name, asc: cmp.name],
        select: %{
          compound: cmp,
          condition: cond,
          recommendation: rec.recommendation,
          severity: rec.severity,
          evidence_level: rec.evidence_level,
          source: rec.source,
          recommendation_id: rec.id,
          relationship_id: scr.id
        }
      )
    )
    |> attach_species_citations()
    # A species can carry a compound via several relationship rows; collapse to one
    # advice line per (condition, compound, recommendation).
    |> Enum.uniq_by(&{&1.condition.id, &1.compound.id, &1.recommendation})
  end

  @doc """
  The ingredients implicated for a condition — a convenience **derived strictly
  through species**: `condition → compound → species → (species' ingredients)`. There
  is no condition↔ingredient or fact↔ingredient link; ingredients are only reachable
  via the `FoundementalFoodSpecies` that carries the compound. Same filtering + shape
  as `species_for_condition/2`, but with `ingredient` in place of `species`.
  """
  def ingredients_for_condition(condition_id, recommendation \\ nil) do
    from(rec in CompoundRecommendation,
      join: scr in SpeciesCompoundRelationship,
      on: scr.compound_id == rec.compound_id,
      join: cmp in Compound,
      on: cmp.id == rec.compound_id,
      join: ff in FoundementalFood,
      on: ff.foundemental_species_id == scr.foundemental_species_id,
      join: ing in assoc(ff, :ingredient),
      where: rec.condition_id == ^condition_id,
      order_by: [asc: ing.name, asc: cmp.name],
      select: %{
        ingredient: ing,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity,
        evidence_level: rec.evidence_level
      }
    )
    |> maybe_filter_recommendation(recommendation)
    |> Repo.all()
  end

  @doc """
  Compound ids a condition recommends to `"encourage"` — the compounds whose
  presence makes a food *good* for the condition. Excludes `non_dietary` compounds.
  Accepts a list of condition ids (empty list → `[]`); returns a deduped list of
  compound ids. Backs the "foods encouraged for a condition" filter on `/foods`.
  """
  def encouraged_compound_ids_for_conditions([]), do: []

  def encouraged_compound_ids_for_conditions(condition_ids) when is_list(condition_ids) do
    Repo.all(
      from(rec in CompoundRecommendation,
        join: cmp in Compound,
        on: cmp.id == rec.compound_id,
        where:
          rec.condition_id in ^condition_ids and rec.recommendation == "encourage" and
            cmp.dietary_relevance != "non_dietary",
        distinct: true,
        select: rec.compound_id
      )
    )
  end

  @discouraged_recommendations ~w(avoid limit caution)

  @doc """
  Encouraged and discouraged **ingredients** for a condition — a convenience over
  `ingredients_for_condition/2` for recipe generation. Encouraged ingredients carry
  a compound the condition recommends to `"encourage"`; discouraged ones carry a
  compound recommended to `"avoid"`, `"limit"`, or `"caution"`. Both lists are the
  bare `Ingredient` structs, deduped by id.

  Returns `%{encouraged: [ingredient], discouraged: [ingredient]}`.
  """
  def ingredient_guidance_for_condition(condition_id) do
    discouraged =
      @discouraged_recommendations
      |> Enum.flat_map(&ingredients_for_condition(condition_id, &1))
      |> Enum.map(& &1.ingredient)
      |> Enum.uniq_by(& &1.id)

    discouraged_ids = MapSet.new(discouraged, & &1.id)

    # An ingredient whose species carries both an "encourage" and an
    # "avoid"/"limit"/"caution" compound would otherwise land in both lists and
    # be seeded as primary AND avoid — a "build around X" / "never use X"
    # contradiction that makes the avoid-guard reject every recipe. Keep such
    # contested ingredients as discouraged only.
    encouraged =
      condition_id
      |> ingredients_for_condition("encourage")
      |> Enum.map(& &1.ingredient)
      |> Enum.uniq_by(& &1.id)
      |> Enum.reject(&MapSet.member?(discouraged_ids, &1.id))

    %{encouraged: encouraged, discouraged: discouraged}
  end

  defp maybe_filter_recommendation(query, nil), do: query

  defp maybe_filter_recommendation(query, recommendation) do
    value = to_string(recommendation)
    from(rec in query, where: rec.recommendation == ^value)
  end

  # ── Condition ↔ nutrient recommendations (numeric fact layer) ─────────────
  # The nutrient sibling of the compound advice layer. Where compounds resolve to
  # foods via the (empty) species-fact table, nutrients resolve via the populated
  # `IngredientNutrient` per-100g table, thresholded through `NutrientTargets`.

  def create_nutrient_recommendation(attrs) do
    %NutrientRecommendation{}
    |> NutrientRecommendation.changeset(attrs)
    |> Repo.insert()
    |> tap_ok()
  end

  @doc """
  Insert or update a nutrient recommendation, keyed on
  `(condition_id, nutrient_name, source)`. Re-asserting from the same source
  overwrites; a different source is kept as a distinct row.
  """
  def upsert_nutrient_recommendation(attrs) do
    %NutrientRecommendation{}
    |> NutrientRecommendation.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:condition_id, :nutrient_name, :source]
    )
    |> tap_ok()
  end

  def delete_nutrient_recommendation(%NutrientRecommendation{} = recommendation),
    do: recommendation |> Repo.delete() |> tap_ok()

  def get_nutrient_recommendation!(id), do: Repo.get!(NutrientRecommendation, id)

  @doc """
  Upsert a condition and link it to a nutrient in one call — the nutrient analog of
  `add_recommendation/3`. `rec_attrs` supplies `recommendation`, `severity`,
  `evidence_level`, `source`, `notes`, `source_reference`.
  """
  def add_nutrient_recommendation(condition_id, nutrient_name, rec_attrs)
      when is_integer(condition_id) do
    rec_attrs
    |> Map.new()
    |> Map.merge(%{condition_id: condition_id, nutrient_name: nutrient_name})
    |> upsert_nutrient_recommendation()
  end

  def add_nutrient_recommendation(condition_attrs, nutrient_name, rec_attrs) do
    with {:ok, condition} <- upsert_condition(condition_attrs) do
      add_nutrient_recommendation(condition.id, nutrient_name, rec_attrs)
    end
  end

  @doc "Nutrient recommendation rows for a condition, name-ordered. Cached."
  def nutrient_recommendations_for_condition(condition_id) do
    key = {@cache_key_ns, {:nutrient_recommendations, condition_id}}

    case Cachex.get(:health_cache, key) do
      {:ok, nil} ->
        result =
          Repo.all(
            from(r in NutrientRecommendation,
              where: r.condition_id == ^condition_id,
              order_by: [asc: r.nutrient_name]
            )
          )

        Cachex.put(:health_cache, key, result, ttl: @cache_ttl)
        result

      {:ok, cached} ->
        cached
    end
  end

  @doc "The distinct nutrient names a set of conditions recommends to `encourage`."
  def encouraged_nutrient_names_for_conditions([]), do: []

  def encouraged_nutrient_names_for_conditions(condition_ids) when is_list(condition_ids),
    do: nutrient_names_for_conditions(condition_ids, ["encourage"])

  @doc "The distinct nutrient names a set of conditions recommends to avoid/limit/caution."
  def discouraged_nutrient_names_for_conditions([]), do: []

  def discouraged_nutrient_names_for_conditions(condition_ids) when is_list(condition_ids),
    do: nutrient_names_for_conditions(condition_ids, @discouraged_recommendations)

  defp nutrient_names_for_conditions(condition_ids, recommendations) do
    Repo.all(
      from(r in NutrientRecommendation,
        where: r.condition_id in ^condition_ids and r.recommendation in ^recommendations,
        distinct: true,
        select: r.nutrient_name
      )
    )
  end

  # Resolve a set of conditions' encouraged nutrient names to
  # `%{label => {nutrient_ids, threshold}}` via NutrientTargets.
  defp encouraged_nutrient_targets(condition_ids) do
    condition_ids
    |> encouraged_nutrient_names_for_conditions()
    |> NutrientTargets.resolve_labels()
  end

  @doc """
  The `FoundementalFoodSpecies` ids implicated for a set of conditions **through
  nutrients** — species whose ingredients are high (≥ target threshold) in a nutrient
  the conditions recommend to `encourage`. Backs the nutrient half of the `/foods`
  filter (unioned with the compound path). Returns `[]` when nothing resolves.
  """
  def encouraged_species_ids_for_conditions([]), do: []

  def encouraged_species_ids_for_conditions(condition_ids) when is_list(condition_ids) do
    case encouraged_nutrient_targets(condition_ids) do
      targets when map_size(targets) == 0 ->
        []

      targets ->
        Repo.all(
          from(inx in IngredientNutrient,
            as: :ing_nut,
            join: ff in FoundementalFood,
            on: ff.ingredient_id == inx.ingredient_id,
            where: ^nutrient_amount_dynamic(targets),
            distinct: true,
            select: ff.foundemental_species_id
          )
        )
    end
  end

  @doc """
  A composable recipe-id subquery for recipes whose ingredients are high in a nutrient
  the given conditions recommend to `encourage` — the nutrient sibling of
  `encouraged_recipe_ids_query/1`. Select shape `%{recipe_id: id}` matches it so the
  two can be `union`ed.
  """
  def nutrient_encouraged_recipe_ids_query(condition_ids) do
    condition_ids
    |> encouraged_nutrient_targets()
    |> nutrient_encouraged_recipe_ids_query_from_targets()
  end

  defp nutrient_encouraged_recipe_ids_query_from_targets(targets) when map_size(targets) == 0,
    do: from(ri in RecipeIngredient, where: fragment("1 = 0"), select: %{recipe_id: ri.recipe_id})

  defp nutrient_encouraged_recipe_ids_query_from_targets(targets) do
    from(ri in RecipeIngredient,
      join: inx in IngredientNutrient,
      as: :ing_nut,
      on: inx.ingredient_id == ri.ingredient_id,
      where: ^nutrient_amount_dynamic(targets),
      distinct: true,
      select: %{recipe_id: ri.recipe_id}
    )
  end

  # An OR-of-(nutrient_id ∈ ids AND amount ≥ threshold) dynamic over the `:ing_nut`
  # binding — each encouraged target carries its own per-100g threshold, so a single
  # `WHERE ... IN` won't do. Assumes a non-empty `targets` map.
  defp nutrient_amount_dynamic(targets) do
    Enum.reduce(targets, nil, fn {_label, {ids, threshold}}, acc ->
      clause = dynamic([ing_nut: inx], inx.nutrient_id in ^ids and inx.amount >= ^threshold)

      case acc do
        nil -> clause
        _ -> dynamic(^acc or ^clause)
      end
    end)
  end

  # ── DB-content localization ───────────────────────────────────────────────
  # Condition/compound/species names + descriptions carry per-language rows in
  # their `*_translation` tables. A locale maps to *several* `language_name` codes
  # (`Locale.data_codes/1`: the canonical ISO code plus legacy aliases, e.g.
  # `"el" => ["el", "Gr"]`) — species/ingredient rows in particular predate the
  # ISO migration and are stored under `"Gr"`, so a query on `"el"` alone silently
  # finds nothing. These helpers batch-load across *all* the locale's codes (no
  # N+1), preferring the canonical ISO row when an entity has both, and overlay
  # them onto the base records with per-field fallback. `nil`/`"en"` is a no-op.

  defp translatable_language?(language), do: language not in [nil, "", "en"]

  defp localize_condition(condition, language) do
    [condition] |> localize_conditions(language) |> hd()
  end

  defp localize_conditions(conditions, language) do
    if translatable_language?(language) do
      codes = Locale.data_codes(language)
      ids = Enum.map(conditions, & &1.id)

      by_id =
        from(t in ConditionTranslation,
          where: t.condition_id in ^ids and t.language_name in ^codes
        )
        |> Repo.all()
        |> best_by_id(codes, & &1.condition_id)

      Enum.map(conditions, fn c ->
        case by_id[c.id] do
          nil -> c
          t -> %{c | name: t.name || c.name, description: t.description || c.description}
        end
      end)
    else
      conditions
    end
  end

  defp localize_recommendation_compounds(rows, language) do
    if translatable_language?(language) do
      names = compound_translation_names(Enum.map(rows, & &1.compound.id), language)
      Enum.map(rows, &%{&1 | compound: apply_compound_name(&1.compound, names)})
    else
      rows
    end
  end

  defp localize_species_rows(rows, language) do
    if translatable_language?(language) do
      compound_names = compound_translation_names(Enum.map(rows, & &1.compound.id), language)
      species_names = species_translation_names(Enum.map(rows, & &1.species.id), language)

      Enum.map(rows, fn row ->
        %{
          row
          | compound: apply_compound_name(row.compound, compound_names),
            species: apply_species_name(row.species, species_names)
        }
      end)
    else
      rows
    end
  end

  defp compound_translation_names([], _language), do: %{}

  defp compound_translation_names(ids, language) do
    codes = Locale.data_codes(language)

    from(t in CompoundTranslation,
      where: t.compound_id in ^ids and t.language_name in ^codes and not is_nil(t.name)
    )
    |> Repo.all()
    |> best_by_id(codes, & &1.compound_id)
    |> Map.new(fn {id, t} -> {id, t.name} end)
  end

  defp species_translation_names([], _language), do: %{}

  defp species_translation_names(ids, language) do
    codes = Locale.data_codes(language)

    from(t in FoundementalFoodSpeciesTranslation,
      where:
        t.foundemental_species_id in ^ids and t.language_name in ^codes and not is_nil(t.name)
    )
    |> Repo.all()
    |> best_by_id(codes, & &1.foundemental_species_id)
    |> Map.new(fn {id, t} -> {id, t.name} end)
  end

  # Collapses translation rows to one per entity id, preferring the row whose
  # `language_name` ranks earliest in `codes` (index 0 = canonical ISO code) when
  # an entity carries both an ISO and a legacy-alias row.
  defp best_by_id(rows, codes, id_fun) do
    rank = codes |> Enum.with_index() |> Map.new()

    rows
    |> Enum.reduce(%{}, fn row, acc ->
      id = id_fun.(row)
      r = Map.get(rank, row.language_name, length(codes))

      case acc do
        %{^id => {best, _}} when best <= r -> acc
        _ -> Map.put(acc, id, {r, row})
      end
    end)
    |> Map.new(fn {id, {_r, row}} -> {id, row} end)
  end

  defp apply_compound_name(compound, names) do
    case names[compound.id] do
      nil -> compound
      name -> %{compound | name: name}
    end
  end

  defp apply_species_name(species, names) do
    case names[species.id] do
      nil -> species
      name -> %{species | name: name}
    end
  end

  @doc """
  Condition badges implicated for a set of recipes, restricted to the given
  opted-in `condition_ids`. Walks `recipe_ingredients → ingredient →
  foundemental_foods → species_compound_relationships → compound_recommendations
  → conditions`, the same composition as `recommendations_for_species/1` but
  anchored on recipes.

  Returns `%{recipe_id => [%{condition, compound, recommendation, severity}]}`,
  deduped per `{recipe_id, condition_id, compound_id, recommendation}`. Recipes
  with no flagged compound are absent from the map. Returns `%{}` immediately
  when either list is empty, so callers can pass a non-opted-in user's empty set
  without hitting the database.
  """
  def flags_for_recipes([], _condition_ids), do: %{}
  def flags_for_recipes(_recipe_ids, []), do: %{}

  def flags_for_recipes(recipe_ids, condition_ids) do
    compound = compound_flags_for_recipes(recipe_ids, condition_ids)
    nutrient = nutrient_flags_for_recipes(recipe_ids, condition_ids)
    Map.merge(compound, nutrient, fn _recipe_id, a, b -> a ++ b end)
  end

  defp compound_flags_for_recipes(recipe_ids, condition_ids) do
    from(ri in RecipeIngredient,
      join: ff in FoundementalFood,
      on: ff.ingredient_id == ri.ingredient_id,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      join: cmp in Compound,
      on: cmp.id == scr.compound_id,
      join: cond in Condition,
      on: cond.id == rec.condition_id,
      where:
        ri.recipe_id in ^recipe_ids and rec.condition_id in ^condition_ids and
          scr.relationship_type != "absent",
      order_by: [asc: cond.name, asc: cmp.name],
      select: %{
        recipe_id: ri.recipe_id,
        condition: cond,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(&{&1.recipe_id, &1.condition.id, &1.compound.id, &1.recommendation})
    |> Enum.group_by(& &1.recipe_id, &Map.delete(&1, :recipe_id))
  end

  # Nutrient-derived badges: a recipe whose ingredients cross a target's per-100g
  # threshold for a nutrient a condition recommends gets a flag. Flags carry a
  # `:label` (nutrient name) + `kind: :nutrient` instead of a `:compound` struct;
  # the renderer reads `flag_label/1` for both kinds.
  defp nutrient_flags_for_recipes(recipe_ids, condition_ids) do
    case nutrient_flag_specs(condition_ids) do
      [] ->
        %{}

      specs ->
        nutrient_ids = specs |> Enum.flat_map(& &1.nutrient_ids) |> Enum.uniq()

        from(ri in RecipeIngredient,
          join: inx in IngredientNutrient,
          on: inx.ingredient_id == ri.ingredient_id,
          where: ri.recipe_id in ^recipe_ids and inx.nutrient_id in ^nutrient_ids,
          select: {ri.recipe_id, inx.nutrient_id, inx.amount}
        )
        |> Repo.all()
        |> build_nutrient_flags(specs)
    end
  end

  # Per-condition nutrient recommendations resolved to `%{condition, nutrient_name,
  # recommendation, severity, nutrient_ids, threshold}` — dropping any whose label
  # resolves to no nutrient rows / no threshold.
  defp nutrient_flag_specs(condition_ids) do
    from(r in NutrientRecommendation,
      join: c in Condition,
      on: c.id == r.condition_id,
      where: r.condition_id in ^condition_ids,
      order_by: [asc: c.name, asc: r.nutrient_name],
      select: %{
        condition: c,
        nutrient_name: r.nutrient_name,
        recommendation: r.recommendation,
        severity: r.severity
      }
    )
    |> Repo.all()
    |> Enum.flat_map(fn spec ->
      case {NutrientTargets.nutrient_ids_for_label(spec.nutrient_name),
            NutrientTargets.threshold(spec.nutrient_name)} do
        {[], _} -> []
        {_ids, nil} -> []
        {ids, threshold} -> [Map.merge(spec, %{nutrient_ids: ids, threshold: threshold})]
      end
    end)
  end

  # Group `{parent_id, nutrient_id, amount}` rows into `%{parent_id => [flag]}`,
  # emitting a flag for each spec whose threshold is crossed by ≥1 of the parent's
  # nutrient amounts. Parents with no crossed spec are dropped.
  defp build_nutrient_flags(rows, specs) do
    rows
    |> Enum.group_by(fn {pid, _nid, _amt} -> pid end, fn {_pid, nid, amt} -> {nid, amt || 0.0} end)
    |> Enum.reduce(%{}, fn {pid, amounts}, acc ->
      case flags_for_amounts(amounts, specs) do
        [] -> acc
        flags -> Map.put(acc, pid, flags)
      end
    end)
  end

  defp flags_for_amounts(amounts, specs) do
    specs
    |> Enum.filter(&spec_crossed?(amounts, &1))
    |> Enum.map(&nutrient_flag/1)
    |> Enum.uniq_by(&{&1.condition.id, &1.label, &1.recommendation})
  end

  # True when ≥1 of the parent's `{nutrient_id, amount}` pairs is one of the spec's
  # target nutrients at or above its per-100g threshold.
  defp spec_crossed?(amounts, spec) do
    id_set = MapSet.new(spec.nutrient_ids)
    Enum.any?(amounts, fn {nid, amt} -> MapSet.member?(id_set, nid) and amt >= spec.threshold end)
  end

  defp nutrient_flag(spec) do
    %{
      condition: spec.condition,
      label: spec.nutrient_name,
      recommendation: spec.recommendation,
      severity: spec.severity,
      kind: :nutrient
    }
  end

  @doc """
  Convenience wrapper over `flags_for_recipes/2` for a single recipe. Returns
  the flag list (possibly empty).
  """
  def flags_for_recipe(recipe_id, condition_ids) do
    flags_for_recipes([recipe_id], condition_ids)
    |> Map.get(recipe_id, [])
  end

  @doc """
  Builds (but does not run) an Ecto `Recipe` query restricted to recipes that
  are **good for** the given conditions — i.e. recipes whose ingredients carry a
  compound the condition recommends to `"encourage"`. Walks the same chain as
  `flags_for_recipes/2` (`recipe_ingredients → ingredient → foundemental_foods →
  species_compound_relationships → compound_recommendations`) as a recipe-id
  subquery so the returned top-level `Recipe` query stays compatible with the
  cursor paginator (`Food.list_recipes/3`, `cursor_fields:
  [{:inserted_at, :asc}, {:id, :asc}]`) and can be further composed with the
  full-text search (`Mehungry.Search.RecipeSearch.run/2`).

  Returns the empty-image-filtered `Recipe` query when `condition_ids` is empty,
  matching the default browse behavior.
  """
  def recipes_for_conditions_query([]), do: from(r in Recipe, where: not is_nil(r.image_url))

  def recipes_for_conditions_query(condition_ids) do
    encouraged_ids =
      from(e in subquery(combined_encouraged_recipe_ids_query(condition_ids)), select: e.recipe_id)

    from(r in Recipe,
      where: not is_nil(r.image_url),
      where: r.id in subquery(encouraged_ids)
    )
  end

  @doc """
  Builds (but does not run) the browse `Recipe` query **prioritized** for the
  given conditions: the full image-filtered catalog, ordered so recipes
  encouraged for the conditions (via `recipes_for_conditions_query/1`'s chain)
  sort to the top, then everything else, each group by `inserted_at`/`id`. This
  is the "prioritize, don't restrict" ordering behind the browse condition
  filter — nothing is hidden, encouraged recipes just lead.

  Because the priority is a computed expression (not a plain column), the
  resulting query is **offset-paginated** via `Food.list_recipes_page/4` rather
  than the cursor paginator. It stays composable with the full-text search
  (`Mehungry.Search.RecipeSearch.run/2`), which appends a rank `order_by` after
  this one, so the priority stays primary and relevance breaks ties.

  Returns the plain image-filtered `Recipe` query when `condition_ids` is empty.
  """
  def recipes_prioritized_for_conditions_query([]),
    do:
      from(r in Recipe, where: not is_nil(r.image_url), order_by: [asc: r.inserted_at, asc: r.id])

  def recipes_prioritized_for_conditions_query(condition_ids) do
    encouraged_ids = combined_encouraged_recipe_ids_query(condition_ids)

    from(r in Recipe,
      left_join: e in subquery(encouraged_ids),
      on: e.recipe_id == r.id,
      where: not is_nil(r.image_url),
      # `e.recipe_id IS NULL` is false (0) for encouraged recipes, true (1) for
      # the rest → ascending puts encouraged first.
      order_by: [asc: fragment("? IS NULL", e.recipe_id), asc: r.inserted_at, asc: r.id]
    )
  end

  # Distinct recipe-id subquery for recipes whose ingredients carry a compound
  # the given conditions recommend to "encourage". Shared by the "encouraged"
  # (`recipes_for_conditions_query/1`) and "prioritized" browse queries so both
  # agree on the same set; `distinct` keeps the prioritized query's left join
  # from multiplying recipe rows.
  defp encouraged_recipe_ids_query(condition_ids) do
    from(ri in RecipeIngredient,
      join: ff in FoundementalFood,
      on: ff.ingredient_id == ri.ingredient_id,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      where:
        rec.condition_id in ^condition_ids and
          rec.recommendation == "encourage" and
          scr.relationship_type != "absent",
      distinct: true,
      select: %{recipe_id: ri.recipe_id}
    )
  end

  # The union of the compound-fact and nutrient-fact "encouraged recipe id"
  # subqueries — the recipe is encouraged if it satisfies *either* engine. When a
  # condition has no resolvable encouraged nutrient, this is just the compound query
  # (avoids an empty `union` leg). Both legs select `%{recipe_id: id}`.
  defp combined_encouraged_recipe_ids_query(condition_ids) do
    compound_query = encouraged_recipe_ids_query(condition_ids)

    case encouraged_nutrient_targets(condition_ids) do
      targets when map_size(targets) == 0 ->
        compound_query

      targets ->
        union(compound_query, ^nutrient_encouraged_recipe_ids_query_from_targets(targets))
    end
  end

  @doc """
  Condition badges implicated for a set of **ingredients**, restricted to the
  given opted-in `condition_ids`. The ingredient-anchored sibling of
  `flags_for_recipes/2`: walks `ingredient → foundemental_foods →
  species_compound_relationships → compound_recommendations → conditions`.

  Returns `%{ingredient_id => [%{condition, compound, recommendation, severity}]}`,
  deduped per `{ingredient_id, condition_id, compound_id, recommendation}`.
  Ingredients with no flagged compound are absent from the map. Returns `%{}`
  immediately when either list is empty, so callers can pass a non-opted-in
  user's empty set without hitting the database.
  """
  def flags_for_ingredients([], _condition_ids), do: %{}
  def flags_for_ingredients(_ingredient_ids, []), do: %{}

  def flags_for_ingredients(ingredient_ids, condition_ids) do
    compound = compound_flags_for_ingredients(ingredient_ids, condition_ids)
    nutrient = nutrient_flags_for_ingredients(ingredient_ids, condition_ids)
    Map.merge(compound, nutrient, fn _ingredient_id, a, b -> a ++ b end)
  end

  defp compound_flags_for_ingredients(ingredient_ids, condition_ids) do
    from(ff in FoundementalFood,
      join: scr in SpeciesCompoundRelationship,
      on: scr.foundemental_species_id == ff.foundemental_species_id,
      join: rec in CompoundRecommendation,
      on: rec.compound_id == scr.compound_id,
      join: cmp in Compound,
      on: cmp.id == scr.compound_id,
      join: cond in Condition,
      on: cond.id == rec.condition_id,
      where:
        ff.ingredient_id in ^ingredient_ids and rec.condition_id in ^condition_ids and
          scr.relationship_type != "absent",
      order_by: [asc: cond.name, asc: cmp.name],
      select: %{
        ingredient_id: ff.ingredient_id,
        condition: cond,
        compound: cmp,
        recommendation: rec.recommendation,
        severity: rec.severity
      }
    )
    |> Repo.all()
    |> Enum.uniq_by(&{&1.ingredient_id, &1.condition.id, &1.compound.id, &1.recommendation})
    |> Enum.group_by(& &1.ingredient_id, &Map.delete(&1, :ingredient_id))
  end

  # Nutrient-derived ingredient badges — the direct `IngredientNutrient` sibling of
  # `nutrient_flags_for_recipes/2` (no recipe_ingredients hop).
  defp nutrient_flags_for_ingredients(ingredient_ids, condition_ids) do
    case nutrient_flag_specs(condition_ids) do
      [] ->
        %{}

      specs ->
        nutrient_ids = specs |> Enum.flat_map(& &1.nutrient_ids) |> Enum.uniq()

        from(inx in IngredientNutrient,
          where: inx.ingredient_id in ^ingredient_ids and inx.nutrient_id in ^nutrient_ids,
          select: {inx.ingredient_id, inx.nutrient_id, inx.amount}
        )
        |> Repo.all()
        |> build_nutrient_flags(specs)
    end
  end

  @doc """
  Convenience wrapper over `flags_for_ingredients/2` for a single ingredient.
  Returns the flag list (possibly empty).
  """
  def flags_for_ingredient(ingredient_id, condition_ids) do
    flags_for_ingredients([ingredient_id], condition_ids)
    |> Map.get(ingredient_id, [])
  end
end
