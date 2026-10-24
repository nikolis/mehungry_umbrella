defmodule Mehungry.Health.ClaimRules do
  @moduledoc """
  A read-only **filter** over the saved `mehungry_extractor` claims
  (`Mehungry.Literature.StudyAnalysis.claims`) that surfaces, per condition,
  ranked **rule candidates** — a dietary entity + a suggested direction
  (`encourage` / `avoid` / `limit` / `review`) + its supporting evidence — so an
  admin can judge whether the extracted literature yields usable
  food-for-condition rules.

  A claim is the normalized concept layer `/analyze` returns: both endpoints
  resolved to a concept (`subject_name` / `object_name`), with a `predicate` +
  `polarity` + `certainty` (see `mehungry_extractor/docs/api.md`).

  The condition side is anchored by the crawl linkage (`study_conditions`): a
  paper is analyzed *for* the condition it was discovered under. The dietary side
  and the direction come from each claim's subject/object + `predicate` +
  `polarity`. This mirrors the valence convention of
  `Mehungry.Health.RecommendationCandidates` (negative → `encourage`, positive →
  `avoid`).

  **Derivation is read-only** — `rules_for_condition/2` persists nothing. It defers
  to the registries (`Food.Compound`, `NutrientTargets`) to resolve a dietary
  endpoint to something that maps to real foods, and flags rules already covered by
  an existing `Health` recommendation. The one write path is `verify_suggestion/3`:
  an explicit human action that promotes a single reviewed suggestion into the
  curated `CompoundRecommendation` / `NutrientRecommendation` layer.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Health.CompoundRecommendation
  alias Mehungry.Health.CompoundRecommendationStudy
  alias Mehungry.Health.ConditionStateRecommendation
  alias Mehungry.Health.ConditionStateRecommendationStudy
  alias Mehungry.Health.NutrientRecommendation
  alias Mehungry.Health.NutrientTargets
  alias Mehungry.Literature
  alias Mehungry.MealBlueprints
  alias Mehungry.Repo

  # A verified suggestion is a recommendation written by this module's own
  # `verify_suggestion/3` — tagged so it can be told apart from hand-curated advice
  # (which this module must never silently manage) and recalled.
  @verification_source "literature"

  # Base valence of a relation predicate, before polarity is applied. Beneficial
  # ⇒ lean `encourage`; harmful ⇒ lean `avoid`; anything unmapped ⇒ `review`.
  # `polarity: "negative"` (the extractor's negation flag) flips the valence.
  @beneficial ~w(improves reduces lowers prevents protects ameliorates alleviates
                 decreases inhibits treats mitigates relieves)
  @harmful ~w(worsens aggravates induces causes increases promotes triggers
              exacerbates elevates raises)

  @doc """
  Ranked rule candidates derived from the stored analyses of a condition's papers.
  Returns a list of maps, most-supported first:

      %{dietary_name, kind, compound_id, nutrient_label, direction, outcome_name,
        predicate, polarity, paper_count, pmids, sources, already_recommended?, score}

  `kind` is `:compound` | `:nutrient` | `:unmatched`; `direction` is
  `"encourage"` | `"avoid"` | `"review"`.
  """
  def rules_for_condition(condition_id, _opts \\ []) do
    reg = registries()
    existing = existing_targets(condition_id, reg)
    # The condition's existing phases. A claim's disease-state is only honored when it
    # matches one of these (we never invent a phase); otherwise it's general advice.
    states = Health.list_states_for_condition(condition_id)

    condition_id
    |> Literature.analyses_for_condition()
    |> Enum.flat_map(&paper_claims/1)
    |> Enum.map(&classify(&1, reg, states))
    # A phase is part of a suggestion's identity: a claim scoped to an existing phase
    # (e.g. "Active Flare") is a different recommendation from the same dietary advice
    # stated in general, so it groups (and verifies) separately. Claims whose disease
    # state matches no existing phase fall into the general (nil-state) bucket.
    |> Enum.group_by(&{&1.dietary_key, &1.direction, &1.state_id || :general})
    |> Enum.map(fn {_key, group} -> aggregate(group, existing) end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  **Human-verify** a derived suggestion by promoting it into the curated advice
  layer — the same `CompoundRecommendation` / `NutrientRecommendation` tables the
  public condition page and the `/conditions` listing already read from (so a
  verified suggestion needs no separate public surface). Written with
  `source: "literature"`.

  `attrs` carries the admin-confirmed `:recommendation` (direction) and optional
  `:severity`; the suggestion's own `direction` is the fallback. A `:compound` one
  promotes to a compound recommendation (its food-related backing studies frozen on
  as citations, mirroring `RecommendationCandidates.promote_candidate/2`), a
  `:nutrient` one to a nutrient recommendation.

  An `:unmatched` suggestion — one whose dietary endpoint resolved to no registry
  entry — maps to no real foods, so it can't drive the shared `/foods`/badge
  surfaces. It is instead published as a **free-text note** on the condition page:
  a general (all-phase, `condition_state_id: nil`) `ConditionStateRecommendation`
  carrying the surface term as `raw_food_term` (`source: "literature"`, backing
  studies frozen). The decoupled phase-aware store is the right home — it already
  renders free-text targets on the condition page and is deliberately kept off the
  food-mapping read surfaces.
  """
  def verify_suggestion(condition_id, rule, attrs \\ %{})

  # Phase-scoped (the claim's disease state matched an existing phase of this
  # condition): the advice goes to the decoupled `ConditionStateRecommendation` store
  # scoped to that `ConditionState`, regardless of target kind. This keeps it distinct
  # from the same target's general advice and surfaces it under the phase selector.
  # We never create a phase here — unmatched disease states are general (`state_id`
  # is nil) and fall through to the general clauses below.
  def verify_suggestion(condition_id, %{state_id: state_id} = rule, attrs)
      when is_integer(state_id) do
    verify_state_suggestion(condition_id, state_id, target_attrs(rule), rule, attrs)
  end

  def verify_suggestion(condition_id, %{kind: :compound, compound_id: compound_id} = rule, attrs)
      when is_integer(compound_id) do
    with {:ok, recommendation} <-
           Health.add_recommendation(condition_id, compound_id, %{
             recommendation: verified_direction(rule, attrs),
             severity: attrs[:severity],
             evidence_level: attrs[:evidence_level] || "limited",
             source: @verification_source,
             notes: verification_note(rule)
           }) do
      freeze_suggestion_studies(recommendation.id, rule)
      {:ok, recommendation}
    end
  end

  def verify_suggestion(condition_id, %{kind: :nutrient, nutrient_label: label} = rule, attrs)
      when is_binary(label) do
    Health.add_nutrient_recommendation(condition_id, label, %{
      recommendation: verified_direction(rule, attrs),
      severity: attrs[:severity],
      evidence_level: attrs[:evidence_level] || "limited",
      source: @verification_source,
      notes: verification_note(rule)
    })
  end

  def verify_suggestion(condition_id, %{kind: :species, species_id: id} = rule, attrs)
      when is_integer(id) do
    verify_state_suggestion(condition_id, nil, %{species_id: id}, rule, attrs)
  end

  def verify_suggestion(condition_id, %{kind: :blueprint, blueprint_id: id} = rule, attrs)
      when is_integer(id) do
    verify_state_suggestion(condition_id, nil, %{blueprint_id: id}, rule, attrs)
  end

  def verify_suggestion(condition_id, %{kind: :unmatched, dietary_name: name} = rule, attrs)
      when is_binary(name) and name != "" do
    verify_state_suggestion(condition_id, nil, %{raw_food_term: name}, rule, attrs)
  end

  def verify_suggestion(_condition_id, _rule, _attrs), do: {:error, :unmatched}

  # The decoupled-store target columns for a rule, by kind (exactly one is set).
  defp target_attrs(%{kind: :compound, compound_id: id}), do: %{compound_id: id}
  defp target_attrs(%{kind: :nutrient, nutrient_label: label}), do: %{nutrient_name: label}
  defp target_attrs(%{kind: :species, species_id: id}), do: %{species_id: id}
  defp target_attrs(%{kind: :blueprint, blueprint_id: id}), do: %{blueprint_id: id}
  defp target_attrs(%{dietary_name: name}), do: %{raw_food_term: name}

  # Shared promotion into the decoupled `ConditionStateRecommendation` store, scoped
  # to `state_id` (`nil` = general/all-phase). Used for targets that don't drive the
  # shared `/foods`/badge surfaces (species / blueprint / free-text) and for *any*
  # phase-scoped target. `target` carries exactly one target column.
  defp verify_state_suggestion(condition_id, state_id, target, rule, attrs) do
    attrs_map =
      Map.merge(target, %{
        condition_id: condition_id,
        condition_state_id: state_id,
        recommendation: verified_direction(rule, attrs),
        severity: attrs[:severity],
        evidence_level: attrs[:evidence_level] || "limited",
        source: @verification_source,
        notes: verification_note(rule)
      })

    with {:ok, recommendation} <- Health.upsert_state_recommendation(attrs_map) do
      freeze_state_suggestion_studies(recommendation.id, rule)
      {:ok, recommendation}
    end
  end

  @doc """
  **Recall** a previously-verified suggestion — the inverse of `verify_suggestion/3`.
  Deletes only the recommendation this module published (`source: "literature"`) for
  the rule's target on the condition; hand-curated advice from any other source is
  left untouched. Frozen citation links cascade with the deleted row. Returns
  `{:ok, count}` (the number of rows removed) or `{:error, :unmatched}`.
  """
  def recall_suggestion(condition_id, rule)

  # Phase-scoped (mirrors the phase-scoped `verify_suggestion/3`): delete the
  # literature-sourced state recommendation for this target under its existing phase.
  def recall_suggestion(condition_id, %{state_id: state_id} = rule)
      when is_integer(state_id) do
    from(r in ConditionStateRecommendation,
      where:
        r.condition_id == ^condition_id and r.condition_state_id == ^state_id and
          r.source == @verification_source
    )
    |> target_where(rule)
    |> recall_state_suggestion()
  end

  def recall_suggestion(condition_id, %{kind: :compound, compound_id: compound_id})
      when is_integer(compound_id) do
    Repo.all(
      from(r in CompoundRecommendation,
        where:
          r.condition_id == ^condition_id and r.compound_id == ^compound_id and
            r.source == @verification_source
      )
    )
    |> tap(&Enum.each(&1, fn rec -> Health.delete_recommendation(rec) end))
    |> then(&{:ok, length(&1)})
  end

  def recall_suggestion(condition_id, %{kind: :nutrient, nutrient_label: label})
      when is_binary(label) do
    Repo.all(
      from(r in NutrientRecommendation,
        where:
          r.condition_id == ^condition_id and r.nutrient_name == ^label and
            r.source == @verification_source
      )
    )
    |> tap(&Enum.each(&1, fn rec -> Health.delete_nutrient_recommendation(rec) end))
    |> then(&{:ok, length(&1)})
  end

  def recall_suggestion(condition_id, %{kind: :species, species_id: id, dietary_name: name})
      when is_integer(id) do
    # Also sweep a stale free-text row for the same species name (verified before the
    # species was curated), so a re-aligned "accepted" suggestion fully recalls.
    norm = normalize(name)

    recall_state_suggestion(
      from(r in ConditionStateRecommendation,
        where:
          r.condition_id == ^condition_id and is_nil(r.condition_state_id) and
            r.source == @verification_source and
            (r.species_id == ^id or fragment("lower(trim(?))", r.raw_food_term) == ^norm)
      )
    )
  end

  def recall_suggestion(condition_id, %{kind: :blueprint, blueprint_id: id}) when is_integer(id) do
    recall_state_suggestion(
      from(r in ConditionStateRecommendation,
        where:
          r.condition_id == ^condition_id and is_nil(r.condition_state_id) and
            r.source == @verification_source and r.blueprint_id == ^id
      )
    )
  end

  def recall_suggestion(condition_id, %{kind: :unmatched, dietary_name: name})
      when is_binary(name) and name != "" do
    norm = normalize(name)

    recall_state_suggestion(
      from(r in ConditionStateRecommendation,
        where:
          r.condition_id == ^condition_id and is_nil(r.condition_state_id) and
            r.source == @verification_source and
            fragment("lower(trim(?))", r.raw_food_term) == ^norm
      )
    )
  end

  def recall_suggestion(_condition_id, _rule), do: {:error, :unmatched}

  # Delete the matched state-store rows (what this module published); returns the count.
  defp recall_state_suggestion(query) do
    query
    |> Repo.all()
    |> tap(&Enum.each(&1, fn rec -> Health.delete_state_recommendation(rec) end))
    |> then(&{:ok, length(&1)})
  end

  # Narrow a state-recommendation query to the rule's target column (exact for
  # registry ids; case-insensitive for the free-text name/nutrient label).
  defp target_where(query, %{kind: :compound, compound_id: id}),
    do: from(r in query, where: r.compound_id == ^id)

  defp target_where(query, %{kind: :species, species_id: id}),
    do: from(r in query, where: r.species_id == ^id)

  defp target_where(query, %{kind: :blueprint, blueprint_id: id}),
    do: from(r in query, where: r.blueprint_id == ^id)

  defp target_where(query, %{kind: :nutrient, nutrient_label: label}) do
    norm = normalize(label)
    from(r in query, where: fragment("lower(trim(?))", r.nutrient_name) == ^norm)
  end

  defp target_where(query, %{dietary_name: name}) do
    norm = normalize(name)
    from(r in query, where: fragment("lower(trim(?))", r.raw_food_term) == ^norm)
  end

  # The admin's confirmed direction, falling back to the suggestion's own; a
  # "review" (undecided) suggestion with no explicit choice lands on "caution".
  defp verified_direction(rule, attrs) do
    case attrs[:recommendation] do
      v when v in ~w(avoid limit caution monitor encourage) -> v
      _ when rule.direction in ~w(avoid limit caution monitor encourage) -> rule.direction
      _ -> "caution"
    end
  end

  # Freeze the suggestion's food-related backing studies onto the recommendation as
  # citations (idempotent), so the public page can link back to the exact papers.
  defp freeze_suggestion_studies(recommendation_id, rule) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      rule.sources
      |> Enum.filter(&(&1.position == "food_related"))
      |> Enum.map(& &1.study_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(
        &%{recommendation_id: recommendation_id, study_id: &1, inserted_at: now, updated_at: now}
      )

    if entries != [], do: Repo.insert_all(CompoundRecommendationStudy, entries, on_conflict: :nothing)
    :ok
  end

  # Freeze an unmatched suggestion's food-related backing studies onto its
  # phase-aware (free-text) recommendation — the `ConditionStateRecommendation`
  # sibling of `freeze_suggestion_studies/2` above.
  defp freeze_state_suggestion_studies(recommendation_id, rule) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      rule.sources
      |> Enum.filter(&(&1.position == "food_related"))
      |> Enum.map(& &1.study_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(
        &%{recommendation_id: recommendation_id, study_id: &1, inserted_at: now, updated_at: now}
      )

    if entries != [],
      do: Repo.insert_all(ConditionStateRecommendationStudy, entries, on_conflict: :nothing)

    :ok
  end

  defp verification_note(rule) do
    pmids = rule.pmids |> Enum.take(10) |> Enum.join(", ")
    base = "Verified from literature suggestions (#{rule.paper_count} food-related paper(s)"
    if pmids != "", do: base <> "; PMIDs #{pmids}).", else: base <> ")."
  end

  @doc """
  Annotate a raw `/analyze` response (for display) with the app-derived layer,
  **without touching the extractor's own fields**. Each claim in
  `paper_claims[]` gets a `"__derived__"` map — what *this app* infers from the
  verbatim claim:

      %{direction, kind, dietary_name, outcome_name, compound_id, nutrient_label,
        used_in_rules?}

  `used_in_rules?` is false for the claims the rule filter drops (hedged, or
  missing an endpoint), so the viewer sees both what came from the API and what we
  add on top. The returned response is otherwise identical — intended for the view
  only, never for persistence.
  """
  def annotate_analysis(response) when is_map(response) do
    reg = registries()

    Map.update(response, "paper_claims", [], fn papers ->
      Enum.map(papers, fn pc ->
        Map.update(pc, "claims_list", [], fn claims ->
          Enum.map(claims, fn claim ->
            Map.put(claim, "__derived__", annotate_claim(claim, reg))
          end)
        end)
      end)
    end)
  end

  # The app-derived layer for a single raw claim (condition-independent).
  defp annotate_claim(claim, reg) do
    claim
    |> derive(reg)
    |> Map.put(:used_in_rules?, usable?(claim))
  end

  # ── Per-paper claim extraction ──────────────────────────────────────────────

  # Each saved claim, tagged with its paper's pmid + study id, keeping only
  # *asserted* relations with both endpoints present (hedged/one-sided ones are
  # dropped). Claims of every curation position are kept here — they all show in
  # the panel (so they can be (re)categorised); the `position` only gates which
  # ones feed the aggregates.
  defp paper_claims(%{claims: claims, study: study, study_id: study_id}) do
    pmid = study && study.pmid

    (claims || [])
    |> Enum.filter(&usable?/1)
    |> Enum.map(&(&1 |> Map.put("__pmid__", pmid) |> Map.put("__study_id__", study_id)))
  end

  defp paper_claims(_), do: []

  # A claim is usable for a rule if it has both endpoints and is either asserted
  # (not hedged) OR the admin explicitly marked it "food_related" — human curation
  # overrides the hedged auto-filter, so a vouched-for "possible" claim still counts.
  defp usable?(claim) do
    endpoint_name(claim, "subject") != nil and endpoint_name(claim, "object") != nil and
      (claim["certainty"] in [nil, "asserted"] or claim["position"] == "food_related")
  end

  # The curation position assigned to a claim (nil when unassigned). Only
  # `food_related` ones feed a rule's aggregates.
  defp position(claim), do: claim["position"]

  # The claim's "disease_state" qualifier value, canonicalized (e.g. "flare",
  # "active disease" → "active flare"), or nil. When present it scopes the suggestion
  # to that phase (claims are grouped by it), mirroring the phase-aware
  # `condition_state_recommendations` model.
  defp disease_state(claim) do
    (claim["qualifiers"] || [])
    |> Enum.find_value(fn q ->
      if q["qualifier_type"] == "disease_state", do: q["value_text"]
    end)
    |> canonical_disease_state()
  end

  # Collapse the extractor's synonymous phase labels to one canonical phrase so
  # claims about the same phase group (and verify) together. The key is the
  # normalized surface text; unknown phrases pass through trimmed (nil stays nil).
  @disease_state_synonyms %{
    "flare" => "active flare",
    "flares" => "active flare",
    "active" => "active flare",
    "active flare" => "active flare",
    "active flares" => "active flare",
    "active disease" => "active flare",
    "active diseases" => "active flare"
  }

  defp canonical_disease_state(nil), do: nil

  defp canonical_disease_state(value) when is_binary(value) do
    case normalize(value) do
      "" -> nil
      norm -> Map.get(@disease_state_synonyms, norm, String.trim(value))
    end
  end

  defp canonical_disease_state(_), do: nil

  # Display order within a rule: the food-related (counted) claims first, then
  # the still-unassigned ones, then the explicitly set-aside ones.
  defp position_rank("food_related"), do: 0
  defp position_rank(nil), do: 1
  defp position_rank("general_science"), do: 2
  defp position_rank("wrong"), do: 3
  defp position_rank("ignore"), do: 4
  defp position_rank(_), do: 5

  # ── Classification: dietary endpoint + direction ────────────────────────────

  # The app-derived layer common to rule derivation and display annotation:
  # which endpoint is dietary, its registry match, and the suggested direction.
  defp derive(claim, reg) do
    subject = endpoint_name(claim, "subject")
    object = endpoint_name(claim, "object")

    {dietary_name, outcome_name, kind, ids} = pick_dietary(subject, object, reg)

    %{
      dietary_name: dietary_name,
      outcome_name: outcome_name,
      kind: kind,
      compound_id: ids[:compound_id],
      nutrient_label: ids[:nutrient_label],
      species_id: ids[:species_id],
      blueprint_id: ids[:blueprint_id],
      direction: direction(claim["predicate"], claim["polarity"])
    }
  end

  defp classify(claim, reg, states) do
    derived = derive(claim, reg)
    # Honor the claim's disease state only when it matches an existing phase of this
    # condition (never invent one); otherwise the claim is general advice.
    {state_id, state_name} = resolve_claim_state(disease_state(claim), states)

    Map.merge(derived, %{
      pmid: claim["__pmid__"],
      study_id: claim["__study_id__"],
      position: position(claim),
      # The matched existing phase (nil when general): its id drives grouping/verify,
      # its name is the label shown.
      state_id: state_id,
      disease_state: state_name,
      # The verbatim API claim backing this rule (our injected keys stripped),
      # carried through so the UI can show the raw extractor payload next to what
      # we derived from it.
      claim: Map.drop(claim, ["__pmid__", "__study_id__"]),
      # Group key: prefer the resolved registry identity so name variants
      # collapse; fall back to the normalized surface name.
      dietary_key: dietary_key(derived)
    })
  end

  # Match a claim's (canonical) disease state to one of the condition's existing
  # phases, returning `{state_id, state_name}`. `{nil, nil}` when the claim carries no
  # disease state, or names a phase the condition doesn't have — such advice is general.
  defp resolve_claim_state(nil, _states), do: {nil, nil}

  defp resolve_claim_state(disease_state, states) do
    key = phase_key(disease_state)

    case Enum.find(states, &(phase_key(&1.name) == key)) do
      %{id: id, name: name} -> {id, name}
      nil -> {nil, nil}
    end
  end

  # Prefer the resolved registry identity (namespaced so a compound #5 and a species
  # #5 never collide); fall back to the normalized surface name when unmatched.
  defp dietary_key(%{compound_id: id}) when is_integer(id), do: {:compound, id}
  defp dietary_key(%{species_id: id}) when is_integer(id), do: {:species, id}
  defp dietary_key(%{blueprint_id: id}) when is_integer(id), do: {:blueprint, id}
  defp dietary_key(%{nutrient_label: l}) when is_binary(l), do: {:nutrient, normalize(l)}
  defp dietary_key(%{dietary_name: name}), do: {:raw, normalize(name)}

  # Choose which endpoint is the dietary one: prefer a food-mapping registry match
  # (compound, then nutrient, then species, then blueprint). If only one endpoint
  # matches, that's the dietary one. If neither matches, fall back to the subject as
  # dietary (tagged :unmatched). If both match, prefer the subject.
  defp pick_dietary(subject, object, reg) do
    sub = resolve(subject, reg)
    obj = resolve(object, reg)

    cond do
      matched?(sub) -> as_dietary(sub, subject, object)
      matched?(obj) -> as_dietary(obj, object, subject)
      true -> {subject, object, :unmatched, %{}}
    end
  end

  defp matched?(:none), do: false
  defp matched?(_), do: true

  defp as_dietary({:compound, id, name}, _raw, outcome),
    do: {name, outcome, :compound, %{compound_id: id}}

  defp as_dietary({:nutrient, label, _n}, dietary, outcome),
    do: {dietary, outcome, :nutrient, %{nutrient_label: label}}

  defp as_dietary({:species, id, name}, _raw, outcome),
    do: {name, outcome, :species, %{species_id: id}}

  defp as_dietary({:blueprint, id, name}, _raw, outcome),
    do: {name, outcome, :blueprint, %{blueprint_id: id}}

  # Resolve a surface term to the highest-priority registry match. Compounds and
  # nutrients win over species/blueprints because they map to foods through the fact
  # tables (a broader food set), but any match beats `:unmatched`.
  defp resolve(name, reg) do
    norm = normalize(name)

    cond do
      c = Map.get(reg.compounds, norm) -> {:compound, c.id, c.name}
      label = Map.get(reg.nutrients, norm) -> {:nutrient, label, name}
      sp = Map.get(reg.species, norm) -> {:species, sp.id, sp.name}
      bp = Map.get(reg.blueprints, norm) -> {:blueprint, bp.id, bp.name}
      true -> :none
    end
  end

  # Predicate base valence flipped by polarity → a suggested direction.
  defp direction(predicate, polarity) do
    base =
      cond do
        is_binary(predicate) and String.downcase(predicate) in @beneficial -> :beneficial
        is_binary(predicate) and String.downcase(predicate) in @harmful -> :harmful
        true -> :unknown
      end

    flipped = if polarity == "negative", do: flip(base), else: base

    case flipped do
      :beneficial -> "encourage"
      :harmful -> "avoid"
      :unknown -> "review"
    end
  end

  defp flip(:beneficial), do: :harmful
  defp flip(:harmful), do: :beneficial
  defp flip(other), do: other

  # ── Aggregation + scoring ───────────────────────────────────────────────────

  defp aggregate([first | _] = group, existing) do
    # The raw API claims backing this rule, paper-tagged — this is the "from the
    # extractor" half the UI renders verbatim. All of them are kept (food-related
    # first) so every claim stays visible and (re)categorisable; only the
    # `food_related` ones feed the counts/score below.
    sources =
      group
      |> Enum.map(fn item ->
        %{
          pmid: item.pmid,
          study_id: item.study_id,
          position: item.position,
          claim: item.claim
        }
      end)
      |> Enum.sort_by(&position_rank(&1.position))

    pmids =
      sources
      |> Enum.filter(&(&1.position == "food_related"))
      |> Enum.map(& &1.pmid)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    rule = %{
      dietary_name: first.dietary_name,
      outcome_name: first.outcome_name,
      kind: first.kind,
      compound_id: first.compound_id,
      nutrient_label: first.nutrient_label,
      species_id: first.species_id,
      blueprint_id: first.blueprint_id,
      direction: first.direction,
      # The existing phase this suggestion is scoped to (nil = general). Drives where a
      # verified suggestion is stored (a phase-scoped `ConditionStateRecommendation`
      # under this state vs the general layer) and the displayed phase label.
      state_id: first.state_id,
      disease_state: first.disease_state,
      disease_states: if(first.disease_state, do: [first.disease_state], else: []),
      paper_count: length(pmids),
      pmids: pmids,
      sources: sources,
      already_recommended?: already_recommended?(first, existing),
      # The direction of this module's own verified recommendation for the target
      # (source "literature"), or nil — drives the verification select's current
      # value and whether a recall is offered.
      verified_as: verified_as(first, existing)
    }

    rule
    |> Map.put(:score, score(rule))
    # A stable identifier so the admin UI can promote exactly this suggestion
    # (re-derived server-side on verify) — see `verify_suggestion/3`.
    |> Map.put(:verify_key, verify_key(rule))
  end

  # Stable within a condition: a suggestion is uniquely its registry target (or
  # normalized name when unmatched) crossed with its direction and disease phase.
  defp verify_key(rule) do
    target =
      rule.compound_id || rule.species_id || rule.blueprint_id || rule.nutrient_label ||
        normalize(rule.dietary_name)

    "#{rule.kind}:#{target}:#{rule.direction}:#{rule_state_key(rule)}"
  end

  # More papers = stronger; a registry-matched entity (maps to real foods or a
  # concrete plan) is worth more than an unmatched name; an undecided direction is
  # demoted.
  defp score(rule) do
    matched_bonus = if rule.kind == :unmatched, do: 0, else: 2
    review_penalty = if rule.direction == "review", do: 1, else: 0
    rule.paper_count * 2 + matched_bonus - review_penalty
  end

  # A phase-scoped suggestion lives only in the state store (keyed by target + phase
  # slug). A general (phase-less) compound/nutrient suggestion is tracked in its own
  # table; a general species/blueprint/free-text one lives in the state store under
  # the "general" phase key.
  defp already_recommended?(rule, existing) do
    cond do
      rule_state_key(rule) != "general" ->
        MapSet.member?(existing.state_all, {rule_target_key(rule), rule_state_key(rule)})

      rule.kind == :compound ->
        MapSet.member?(existing.compound_ids, rule.compound_id)

      rule.kind == :nutrient ->
        MapSet.member?(existing.nutrient_names, normalize(rule.nutrient_label))

      true ->
        MapSet.member?(existing.state_all, {rule_target_key(rule), "general"})
    end
  end

  # The direction of *this module's* verified recommendation for the rule's target +
  # phase, or nil. Distinct from `already_recommended?/2`, which counts advice from
  # any source (incl. hand-curated), so the UI can offer a recall only for what it owns.
  defp verified_as(rule, existing) do
    cond do
      rule_state_key(rule) != "general" ->
        Map.get(existing.state_verified, {rule_target_key(rule), rule_state_key(rule)})

      rule.kind == :compound ->
        Map.get(existing.compound_verified, rule.compound_id)

      rule.kind == :nutrient ->
        Map.get(existing.nutrient_verified, normalize(rule.nutrient_label))

      true ->
        Map.get(existing.state_verified, {rule_target_key(rule), "general"})
    end
  end

  # A stable per-target key shared by a rule and a stored state recommendation, so
  # the two can be matched across the general/phase stores.
  defp rule_target_key(%{kind: :compound, compound_id: id}), do: "c#{id}"
  defp rule_target_key(%{kind: :nutrient, nutrient_label: label}), do: "n#{normalize(label)}"
  defp rule_target_key(%{kind: :species, species_id: id}), do: "s#{id}"
  defp rule_target_key(%{kind: :blueprint, blueprint_id: id}), do: "b#{id}"
  defp rule_target_key(%{dietary_name: name}), do: "r#{normalize(name)}"

  # A stored rec's target key. A free-text `raw_food_term` that now matches a curated
  # species keys as that species — so a suggestion verified while the term was unknown
  # still lines up (as "accepted") once the species is curated, rather than orphaning.
  defp rec_target_key(rec, species_by_name) do
    cond do
      rec.compound_id -> "c#{rec.compound_id}"
      rec.species_id -> "s#{rec.species_id}"
      rec.blueprint_id -> "b#{rec.blueprint_id}"
      present?(rec.nutrient_name) -> "n#{normalize(rec.nutrient_name)}"
      present?(rec.raw_food_term) -> raw_target_key(rec.raw_food_term, species_by_name)
      true -> "r#{normalize(rec.raw_food_term)}"
    end
  end

  defp raw_target_key(raw, species_by_name) do
    norm = normalize(raw)

    case Map.get(species_by_name, norm) do
      %{id: id} -> "s#{id}"
      _ -> "r#{norm}"
    end
  end

  # The phase key for a rule/recommendation — the matched `ConditionState` id, or
  # "general" when phase-less. An integer id keys exactly (the canonical-name match
  # already happened when the claim was resolved to an existing phase).
  defp rule_state_key(%{state_id: id}) when is_integer(id), do: id
  defp rule_state_key(_), do: "general"

  defp rec_state_key(%{condition_state_id: id}) when is_integer(id), do: id
  defp rec_state_key(_), do: "general"

  # The canonical, normalized disease phase (so "flare"/"active disease"/"Active Flare"
  # all key the same), or "general" when absent. Used to match a claim's disease state
  # to an existing phase by name.
  defp phase_key(nil), do: "general"

  defp phase_key(label) when is_binary(label) do
    case canonical_disease_state(label) do
      nil -> "general"
      canon -> normalize(canon)
    end
  end

  # ── Registries / lookups ────────────────────────────────────────────────────

  # The registries a claim's dietary endpoint is matched against, built once per
  # derivation pass: compounds + nutrients (which map to real foods via the fact
  # tables), food species (matched by name *or* scientific name), and public meal
  # blueprints (matched by name). Threaded as a single map so adding a registry
  # doesn't ripple through every signature.
  defp registries do
    %{
      compounds: compounds_by_name(),
      nutrients: normalized_nutrient_labels(),
      species: species_by_name(),
      blueprints: blueprints_by_name()
    }
  end

  defp compounds_by_name do
    Food.list_compounds()
    |> Map.new(fn c -> {normalize(c.name), c} end)
  end

  defp normalized_nutrient_labels do
    NutrientTargets.labels()
    |> Map.new(fn label -> {normalize(label), label} end)
  end

  # Species keyed on both their `name` and `scientific_name` (either can match a
  # claim's surface term). A later key wins on collision; names are distinct enough
  # in practice that this is fine.
  defp species_by_name do
    Food.list_foundemental_species()
    |> Enum.reduce(%{}, fn sp, acc ->
      acc
      |> maybe_put_species(sp.name, sp)
      |> maybe_put_species(sp.scientific_name, sp)
    end)
  end

  defp maybe_put_species(acc, name, _sp) when name in [nil, ""], do: acc
  defp maybe_put_species(acc, name, sp), do: Map.put(acc, normalize(name), sp)

  # Public (browsable) blueprints keyed on normalized name — private ones are never
  # surfaced on the public condition page, so they aren't matchable.
  defp blueprints_by_name do
    MealBlueprints.list_public_blueprints()
    |> Map.new(fn bp -> {normalize(bp.name), bp} end)
  end

  # The condition's existing advice, indexed so a derived rule can be flagged as
  # already covered (any source) and as verified-by-this-module (source
  # "literature", mapped target → direction for the select's current value).
  #
  # Compound/nutrient *general* advice lives in its own tables; everything else —
  # species/blueprint/free-text, plus any phase-scoped advice of any kind — lives in
  # the decoupled state store, indexed by `{target_key, phase_slug}`.
  defp existing_targets(condition_id, reg) do
    compound_recs = Health.recommendations_for_condition(condition_id)
    nutrient_recs = Health.nutrient_recommendations_for_condition(condition_id)
    state_recs = Health.list_all_state_recommendations_for_condition(condition_id)
    species = reg.species

    %{
      compound_ids: MapSet.new(compound_recs, & &1.compound_id),
      nutrient_names: MapSet.new(nutrient_recs, &normalize(&1.nutrient_name)),
      compound_verified:
        compound_recs
        |> Enum.filter(&(&1.source == @verification_source))
        |> Map.new(&{&1.compound_id, &1.recommendation}),
      nutrient_verified:
        nutrient_recs
        |> Enum.filter(&(&1.source == @verification_source))
        |> Map.new(&{normalize(&1.nutrient_name), &1.recommendation}),
      state_all: MapSet.new(state_recs, &{rec_target_key(&1, species), rec_state_key(&1)}),
      state_verified:
        state_recs
        |> Enum.filter(&(&1.source == @verification_source))
        |> Map.new(&{{rec_target_key(&1, species), rec_state_key(&1)}, &1.recommendation})
    }
  end

  defp present?(v), do: is_binary(v) and v != ""

  # ── Small helpers ───────────────────────────────────────────────────────────

  # The canonical name of an endpoint: the resolved concept name, else the raw
  # surface text. (`*_label` folds in modifiers and isn't a clean entity name, so
  # it isn't used for registry matching.)
  defp endpoint_name(claim, side) do
    claim["#{side}_name"] || claim["#{side}_text"]
  end

  defp normalize(nil), do: nil
  defp normalize(name) when is_binary(name), do: name |> String.trim() |> String.downcase()
end
