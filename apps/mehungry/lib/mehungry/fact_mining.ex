defmodule Mehungry.FactMining do
  @moduledoc """
  Context for the external **biomed-fact-miner** integration — the pipeline that
  replaced the old `Mehungry.CompoundPipeline` species↔compound derivation.

  Two entity surfaces share the machinery, each asking the miner a different
  question and storing the returned `FactSheet.facts` as distilled, PMID-cited
  claims carrying the API's honest verification `label` (verified / contradicted /
  unverified_*). Mining **fully replaces** that entity's previous facts
  (wipe-then-insert), so a re-run is idempotent.

  - **Species** — an **entity-scope** question (`"tell me all the facts about
    {name} ({scientific_name})"`) → `SpeciesMinedFact` rows (`mine_species/1`).
  - **Condition** — a **relational** question (`"give me all the food related
    facts about {condition}"`) → `ConditionMinedFact` rows (`mine_condition/1`),
    with each mined PMID enriched into the `ScientificStudy` registry for
    publication-card metadata, read back by `research_for_condition/1` /
    `conditions_for_search/1` (the nutritionist research surface). A publication is
    **presentable** (shown with verbatim quotes) only when its source licence is
    `commercial_ok`; everything else is a "free claim" (distilled text + link).

  `connection/0` resolves the service `{base_url, auth_token}` — a UI-managed
  singleton (`Settings`, editable at `/professional/health`) falling back to the
  `:fact_miner_base_url` / `:fact_miner_auth_token` config (`FACT_MINER_BASE_URL` /
  `FACT_MINER_AUTH_TOKEN` env; default `http://127.0.0.1:8811`). The token is sent
  as `Authorization: Bearer <jwt>`. `client/0` is the `:fact_miner_client` seam
  tests swap for a stub. See `docs/implementation/fact_mining.md`.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.FoundementalFoodSpecies
  alias Mehungry.Health
  alias Mehungry.Health.Condition
  alias Mehungry.Literature
  alias Mehungry.Literature.{JournalAuthority, ResearchType, ScientificStudy}
  alias Mehungry.FactMining.{ConditionMinedFact, Settings, SpeciesMinedFact}

  @default_base_url "http://127.0.0.1:8811"

  @doc "The persisted singleton connection settings row, or `nil` when none saved."
  def get_settings, do: Repo.one(from(s in Settings, order_by: [asc: s.id], limit: 1))

  @doc "Upsert the singleton fact-miner connection settings (URL + optional JWT)."
  def update_settings(attrs) do
    (get_settings() || %Settings{})
    |> Settings.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  The live `{base_url, auth_token}` for the fact-miner service. `base_url` has its
  trailing slash trimmed; `auth_token` (a JWT/bearer token) is `nil` when unset.
  Prefers the UI-saved row, falling back to the `:fact_miner_base_url` /
  `:fact_miner_auth_token` config (`FACT_MINER_BASE_URL` / `FACT_MINER_AUTH_TOKEN`
  env), then the built-in default `#{@default_base_url}` (deliberately distinct from
  the extractor's `:8000`).
  """
  def connection do
    settings = get_settings()

    base_url =
      (settings && settings.base_url) ||
        Application.get_env(:mehungry, :fact_miner_base_url) || @default_base_url

    auth_token =
      case settings do
        %Settings{auth_token: token} when is_binary(token) and token != "" ->
          token

        _ ->
          case Application.get_env(:mehungry, :fact_miner_auth_token) do
            token when is_binary(token) and token != "" -> token
            _ -> nil
          end
      end

    {String.trim_trailing(base_url, "/"), auth_token}
  end

  @doc """
  The live base URL for the fact-miner service, trailing slash trimmed — the URL
  half of `connection/0` (kept for callers that only need the host).
  """
  def base_url do
    {base_url, _auth_token} = connection()
    base_url
  end

  @doc """
  The configured fact-miner client module (`:fact_miner_client`, default
  `Mehungry.FactMining.Client`) — the one seam tests swap for a stub.
  """
  def client, do: Application.get_env(:mehungry, :fact_miner_client, Mehungry.FactMining.Client)

  @doc "Pre-flight liveness probe against the miner: `:ok` or `{:error, reason}`."
  def reachable?, do: client().reachable?()

  @doc """
  The entity-scope question for a species: `"tell me all the facts about Acerola
  (Malpighia emarginata)"`. Drops the parenthetical when there is no
  `scientific_name`.
  """
  def query_for_species(%FoundementalFoodSpecies{name: name, scientific_name: sci})
      when is_binary(sci) and sci != "" do
    "tell me all the facts about #{name} (#{sci})"
  end

  def query_for_species(%FoundementalFoodSpecies{name: name}) do
    "tell me all the facts about #{name}"
  end

  @doc """
  Mine one species and **replace** its stored facts. Calls the miner with the
  species' entity query, maps the returned `FactSheet` into rows, and wipe-inserts
  them in a single transaction. Returns `{:ok, counts}` (`%{total, verified,
  contradicted, by_label}`) or `{:error, reason}` on a non-200 / parse failure (so
  the worker can let Oban retry).

  `opts[:query]` overrides the prompt sent to the miner (blank/nil → the default
  `query_for_species/1`), letting the admin customize the question per mine.
  """
  def mine_species(species_or_id, opts \\ [])

  def mine_species(%FoundementalFoodSpecies{} = species, opts) do
    query = presence(Keyword.get(opts, :query)) || query_for_species(species)

    case client().mine(query, max_records: 200) do
      {:ok, sheet} ->
        rows = map_fact_sheet(sheet, :foundemental_species_id, species.id)
        counts = count_rows(rows)

        Repo.transaction(fn ->
          Repo.delete_all(
            from(f in SpeciesMinedFact, where: f.foundemental_species_id == ^species.id)
          )

          if rows != [], do: Repo.insert_all(SpeciesMinedFact, rows)
        end)

        {:ok, counts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def mine_species(species_id, opts) when is_integer(species_id) do
    mine_species(Food.get_foundemental_species!(species_id), opts)
  end

  @doc """
  The **relational** question for a condition: `"give me all the food related
  facts about Ulcerative Colitis"`.
  """
  def query_for_condition(%Condition{name: name}) do
    "give me all the food related facts about #{name}"
  end

  @doc """
  Mine one condition and **replace** its stored facts. Calls the miner with the
  condition's relational query, maps the returned `FactSheet` into
  `ConditionMinedFact` rows, wipe-inserts them in a single transaction, then
  **enriches** each distinct `pmid` into the `ScientificStudy` registry (so the
  nutritionist publication cards carry real title/journal/authors/year — the miner
  returns only PMID/PMCID/DOI). Enrichment is best-effort and cached
  (`Literature.fetch_and_upsert_study/1` returns the stored row with no network
  when present), so a re-run is cheap. Returns `{:ok, counts}` or
  `{:error, reason}` on a non-200 / parse failure (so the worker can let Oban retry).

  `opts[:query]` overrides the prompt sent to the miner (blank/nil → the default
  `query_for_condition/1`), letting the admin customize the question per mine.
  """
  def mine_condition(condition_or_id, opts \\ [])

  def mine_condition(%Condition{} = condition, opts) do
    query = presence(Keyword.get(opts, :query)) || query_for_condition(condition)

    case client().mine(query, max_records: 200) do
      {:ok, sheet} ->
        rows = map_fact_sheet(sheet, :condition_id, condition.id)
        counts = count_rows(rows)

        Repo.transaction(fn ->
          Repo.delete_all(from(f in ConditionMinedFact, where: f.condition_id == ^condition.id))
          if rows != [], do: Repo.insert_all(ConditionMinedFact, rows)
        end)

        enrich_publications(rows)

        {:ok, counts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def mine_condition(condition_id, opts) when is_integer(condition_id) do
    mine_condition(Health.get_condition!(condition_id), opts)
  end

  # Upsert each mined PMID into the study registry so publication cards have
  # metadata. Best-effort: a PMID that fails efetch simply has no card metadata.
  defp enrich_publications(rows) do
    rows
    |> Enum.map(& &1.pmid)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> Enum.each(fn pmid ->
      case Literature.fetch_and_upsert_study(pmid) do
        {:ok, _study} -> :ok
        _ -> :ok
      end
    end)
  end

  @doc """
  Flatten a `FactSheet.to_dict()` map into mined-fact row maps for
  `Repo.insert_all` (atom keys + explicit timestamps). `owner_field` is the owning
  FK column — `:foundemental_species_id` for `SpeciesMinedFact` or `:condition_id`
  for `ConditionMinedFact` — set to `owner_id` on every row. The verbatim `quote`
  is kept **only** for `commercial_ok` sources; otherwise it is dropped (the API
  already redacts it under `?view=public`). Facts missing a `fact_id`/`text`/`label`
  are skipped, and duplicate `fact_id`s within a sheet are de-duplicated (the
  natural key is `(owner, fact_id)`).
  """
  def map_fact_sheet(%{} = sheet, owner_field, owner_id) when is_atom(owner_field) do
    scope_kind = sheet["scope_kind"]
    # insert_all bypasses autogeneration; `timestamps()` columns are :naive_datetime.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    (sheet["facts"] || [])
    |> Enum.map(&row_from_verdict(&1, owner_field, owner_id, scope_kind, now))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.fact_id)
  end

  defp row_from_verdict(%{"fact" => %{} = fact} = verdict, owner_field, owner_id, scope_kind, now) do
    fact_id = fact["fact_id"]
    text = fact["text"]
    label = verdict["label"]

    if blank?(fact_id) or blank?(text) or blank?(label) do
      nil
    else
      # `lay` is a FactVerdict-level block (sibling to label/certainty), not inside
      # `fact`; absent on facts mined before the miner exposed it → all-nil.
      lay = verdict["lay"] || %{}

      %{
        owner_field => owner_id,
        label: label,
        certainty: verdict["certainty"],
        reason: verdict["reason"],
        conflicting_pmid: verdict["conflicting_pmid"],
        assessment: verdict["assessment"],
        lay_tier: lay["tier"],
        lay_clarity: lay["clarity"],
        lay_flags: lay["flags"],
        fact_id: fact_id,
        text: text,
        claim_type: fact["claim_type"],
        evidence_id: fact["evidence_id"],
        pmid: fact["pmid"],
        quote: quote_for(fact),
        char_span: fact["char_span"],
        study_design: fact["study_design"],
        source: fact["source"],
        pmcid: fact["pmcid"],
        doi: fact["doi"],
        pub_status: fact["pub_status"],
        structured_effect: fact["structured_effect"],
        license: fact["license"],
        license_raw: fact["license_raw"],
        scope_kind: scope_kind,
        inserted_at: now,
        updated_at: now
      }
    end
  end

  defp row_from_verdict(_other, _owner_field, _owner_id, _scope_kind, _now), do: nil

  # Store the verbatim quote only for commercial_ok sources; never persist the
  # "[quote withheld — … license]" placeholder the API returns for the rest.
  defp quote_for(%{"license" => "commercial_ok", "quote" => q}) when is_binary(q), do: q
  defp quote_for(_fact), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  # A trimmed non-empty string, else nil — so an empty custom-prompt textarea
  # falls back to the default query builder.
  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_), do: nil

  defp count_rows(rows) do
    by_label = Enum.frequencies_by(rows, & &1.label)

    %{
      total: length(rows),
      verified: Map.get(by_label, "verified", 0),
      contradicted: Map.get(by_label, "contradicted", 0),
      by_label: by_label
    }
  end

  # ── Reads (the surfaces: species detail page, research reader, species API) ──

  @doc """
  Mined facts for a species, newest-mined first. `opts[:labels]` filters to a list
  of labels (e.g. `["verified", "contradicted"]`); omit for all labels.
  """
  def list_facts_for_species(species_id, opts \\ []) do
    labels = Keyword.get(opts, :labels)

    SpeciesMinedFact
    |> where([f], f.foundemental_species_id == ^species_id)
    |> then(fn q -> if labels, do: where(q, [f], f.label in ^labels), else: q end)
    |> order_by([f], asc: f.fact_id)
    |> Repo.all()
  end

  @doc "How many mined facts a species has (optionally filtered by `:labels`)."
  def count_facts_for_species(species_id, opts \\ []) do
    labels = Keyword.get(opts, :labels)

    SpeciesMinedFact
    |> where([f], f.foundemental_species_id == ^species_id)
    |> then(fn q -> if labels, do: where(q, [f], f.label in ^labels), else: q end)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Mined-fact counts for every species that has any, as a `%{species_id => count}`
  map — one grouped query (species with no facts are simply absent). Used to
  annotate the admin species picker.
  """
  def fact_counts_by_species do
    SpeciesMinedFact
    |> group_by([f], f.foundemental_species_id)
    |> select([f], {f.foundemental_species_id, count(f.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The curated, SEO-visible research set for a species' detail page: the on-subject
  **verified** facts only, ranked lead-tier → name-mention → clarity, capped at
  `:limit` (default 10).

  A well-studied species can carry thousands of mined facts; rendering them all
  bloats the page (HTML weight + crawl) without SEO benefit. This returns the small
  high-signal set shown on first paint — everything else is reachable via
  `search_facts_for_species/3`. Off-subject facts (`lay_tier == "hide"`, the miner's
  comparator/background relevance call) are excluded. Facts mined before the miner
  exposed `lay` have NULL `lay_tier`/`lay_clarity` and are kept (not hidden), ordered
  behind the lead-tier ones; `:name_term` (a species-name stem, e.g. `"cranberr"`)
  then boosts facts that name the food — the transitional fallback until a re-mine
  populates `lay`.
  """
  def top_facts_for_species(species_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    term = opts |> Keyword.get(:name_term) |> normalize_term()

    base =
      SpeciesMinedFact
      |> where([f], f.foundemental_species_id == ^species_id)
      |> where([f], f.label == "verified")
      |> where([f], is_nil(f.lay_tier) or f.lay_tier != "hide")

    base
    |> top_order(term)
    |> limit(^limit)
    |> Repo.all()
  end

  # Upper bound on the verified pool re-sorted in Elixir by evidence altitude.
  # A species rarely carries more than a few hundred verified facts; this bounds
  # the work on a pathological one while still giving the diet-relevant buckets a
  # full chance to surface ahead of the mechanistic pile.
  @curated_pool_limit 200

  @doc """
  The species page's curated findings, **split by evidence altitude** —
  `%{relevant: [...], mechanistic: [...], mechanistic_count: n}`.

  `relevant` leads with human/clinical evidence; `mechanistic` is the
  `ResearchType` `:preclinical_other` pile (molecular docking, in-vitro, animal)
  that a diet-watcher can't read, demoted so the page doesn't open on a wall of
  bench chemistry. Unclassified designs stay in `relevant` (not provably lab-only).

  Ordering: the verified, non-`hide` pool is pulled in the existing lay order
  (`top_order/2` — lead tier, name mention, clarity), then **stably** re-sorted by
  `ResearchType.order/1` so stronger evidence rises *without* losing the lay
  ranking within a bucket. Each list is capped at `:limit` (default 10). The
  honest totals shown in the header come from `research_counts_for_species/1`,
  unaffected by this split.
  """
  def curated_facts_for_species(species_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    term = opts |> Keyword.get(:name_term) |> normalize_term()

    pool =
      SpeciesMinedFact
      |> where([f], f.foundemental_species_id == ^species_id)
      |> where([f], f.label == "verified")
      |> where([f], is_nil(f.lay_tier) or f.lay_tier != "hide")
      |> top_order(term)
      |> limit(^@curated_pool_limit)
      |> Repo.all()

    {mechanistic, relevant} =
      pool
      |> Enum.sort_by(&ResearchType.order(ResearchType.bucket(&1.study_design)))
      |> Enum.split_with(&(ResearchType.bucket(&1.study_design) == :preclinical_other))

    %{
      relevant: Enum.take(relevant, limit),
      mechanistic: Enum.take(mechanistic, limit),
      mechanistic_count: length(mechanistic)
    }
  end

  # Postgres sorts booleans false < true, so `desc:` on a boolean expression puts
  # the matches (lead tier / name mention) first; NULL clarity coalesces to 0 (last).
  defp top_order(query, nil) do
    order_by(query, [f],
      desc: fragment("(? = 'lead')", f.lay_tier),
      desc: fragment("coalesce(?, 0)", f.lay_clarity),
      asc: f.fact_id
    )
  end

  defp top_order(query, term) do
    like = "%" <> term <> "%"

    order_by(query, [f],
      desc: fragment("(? = 'lead')", f.lay_tier),
      desc: fragment("(? ilike ?)", f.text, ^like),
      desc: fragment("coalesce(?, 0)", f.lay_clarity),
      asc: f.fact_id
    )
  end

  @doc """
  A crude singular stem of a species' English common name's first token
  ("Cranberries (Alaska Native)" → "cranberr", "Tomatoes" → "tomato") — the
  `:name_term` for `curated_facts_for_species/2`, boosting facts that name the food
  when `lay` relevance is absent (pre-re-mine data). English name on purpose: mined
  fact text is English regardless of UI locale. `nil` when there is no usable name.
  """
  def species_name_term(%{name: name}) when is_binary(name) do
    core =
      name
      |> String.split(["(", ",", "/"], parts: 2)
      |> List.first()
      |> String.trim()
      |> String.downcase()

    cond do
      core == "" -> nil
      String.ends_with?(core, "ies") -> String.replace_suffix(core, "ies", "")
      String.ends_with?(core, "es") -> String.replace_suffix(core, "es", "")
      String.ends_with?(core, "s") -> String.replace_suffix(core, "s", "")
      true -> core
    end
  end

  def species_name_term(_), do: nil

  defp normalize_term(term) when is_binary(term) do
    case String.trim(term) do
      "" -> nil
      t -> t
    end
  end

  defp normalize_term(_), do: nil

  @doc """
  Verdict tally `%{verified:, contradicted:, unverified:, total:}` for a species —
  one grouped aggregate (not a row scan), so the honest "N corroborated / N
  contradicted / N unverified" header is cheap even when the curated render shows
  only the top 10.
  """
  def research_counts_for_species(species_id) do
    by_label =
      SpeciesMinedFact
      |> where([f], f.foundemental_species_id == ^species_id)
      |> group_by([f], f.label)
      |> select([f], {f.label, count(f.id)})
      |> Repo.all()
      |> Map.new()

    verified = Map.get(by_label, "verified", 0)
    contradicted = Map.get(by_label, "contradicted", 0)
    total = by_label |> Map.values() |> Enum.sum()

    %{
      verified: verified,
      contradicted: contradicted,
      unverified: total - verified - contradicted,
      total: total
    }
  end

  @doc """
  Fuzzy substring search over a species' mined facts (case-insensitive `ILIKE` on
  the distilled `text`), across **all** labels and tiers — so corroborated,
  contradicted, unverified, and off-subject facts are all findable. This is the
  on-demand path for the bulk the curated top set omits; a blank query returns `[]`.
  Capped at `:limit` (default 30).
  """
  def search_facts_for_species(species_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)

    case normalize_term(query) do
      nil ->
        []

      term ->
        like = "%" <> term <> "%"

        SpeciesMinedFact
        |> where([f], f.foundemental_species_id == ^species_id)
        |> where([f], ilike(f.text, ^like))
        |> order_by([f],
          desc: fragment("(? = 'verified')", f.label),
          desc: fragment("(? = 'lead')", f.lay_tier),
          desc: fragment("coalesce(?, 0)", f.lay_clarity),
          asc: f.fact_id
        )
        |> limit(^limit)
        |> Repo.all()
    end
  end

  # ── Condition reads (the nutritionist research surface) ──────────────────────

  @doc "Mined facts for a condition, ordered by `fact_id`. `opts[:labels]` filters labels."
  def list_facts_for_condition(condition_id, opts \\ []) do
    labels = Keyword.get(opts, :labels)

    ConditionMinedFact
    |> where([f], f.condition_id == ^condition_id)
    |> then(fn q -> if labels, do: where(q, [f], f.label in ^labels), else: q end)
    |> order_by([f], asc: f.fact_id)
    |> Repo.all()
  end

  @doc "How many mined facts a condition has (optionally filtered by `:labels`)."
  def count_facts_for_condition(condition_id, opts \\ []) do
    labels = Keyword.get(opts, :labels)

    ConditionMinedFact
    |> where([f], f.condition_id == ^condition_id)
    |> then(fn q -> if labels, do: where(q, [f], f.label in ^labels), else: q end)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Mined-fact tallies for many conditions in a single query — `%{condition_id =>
  %{total: n, verified: n}}`, defaulting every id to zeros. Lets the admin
  condition list show a per-card count (and a link to the research surface where
  the facts actually render) without an N+1 over ~200 conditions.
  """
  def fact_counts_by_conditions(condition_ids) when is_list(condition_ids) do
    rows =
      ConditionMinedFact
      |> where([f], f.condition_id in ^condition_ids)
      |> group_by([f], [f.condition_id, f.label])
      |> select([f], {f.condition_id, f.label, count(f.id)})
      |> Repo.all()

    base = Map.new(condition_ids, fn id -> {id, %{total: 0, verified: 0}} end)

    Enum.reduce(rows, base, fn {cid, label, n}, acc ->
      Map.update!(acc, cid, fn %{total: t, verified: v} ->
        %{total: t + n, verified: v + if(label == "verified", do: n, else: 0)}
      end)
    end)
  end

  @label_order %{
    "verified" => 0,
    "contradicted" => 1,
    "unverified_insufficient" => 2,
    "unverified_fulltext" => 3,
    "unverified_quality" => 4,
    "unverified_verification" => 5
  }

  @doc """
  The nutritionist research payload for one condition, built from its stored
  `ConditionMinedFact`s (no extractor involvement). Facts are grouped by `pmid`
  into **publications**, each joined to its `ScientificStudy` (by pmid) for
  metadata. A publication whose source licence is `commercial_ok` is
  **presentable** (we may show its verbatim quotes); everything else is a **free
  claim** (distilled text + source link only). Returns:

      %{
        groups:            [%{key, label, order, publications: [pub]}],  # presentable, by research type
        free_publications: [pub],                                         # non-presentable (verified facts first)
        publication_count: integer,
        fact_count: integer
      }

  where each `pub` is a map `%{pmid, pmcid, doi, study, study_id, title, journal,
  authors, publication_year, medline?, bucket, presentable?, facts}` and each
  `fact` is a `%ConditionMinedFact{}` (verified first within the publication).
  """
  def research_for_condition(condition_id) do
    facts =
      ConditionMinedFact
      |> where([f], f.condition_id == ^condition_id)
      |> Repo.all()

    studies = studies_by_pmid(facts)

    publications =
      facts
      |> Enum.group_by(& &1.pmid)
      |> Enum.map(fn {pmid, pmid_facts} -> build_publication(pmid, pmid_facts, studies) end)

    {presentable, restricted} = Enum.split_with(publications, & &1.presentable?)

    groups =
      presentable
      |> Enum.group_by(& &1.bucket)
      |> Enum.map(fn {bucket, pubs} ->
        %{
          key: bucket,
          label: ResearchType.label(bucket),
          order: ResearchType.order(bucket),
          publications: Enum.sort_by(pubs, &publication_sort_key/1)
        }
      end)
      |> Enum.sort_by(& &1.order)

    free_publications = Enum.sort_by(restricted, &publication_sort_key/1)

    %{
      groups: groups,
      free_publications: free_publications,
      publication_count: length(publications),
      fact_count: length(facts)
    }
  end

  @doc """
  Within-condition full-text search over a condition's mined research. Returns a
  flat, **rank-ordered** list of publications matching `query`, each the same
  `build_publication/3` shape plus `:rank` (float) and `:matched_in_finding`
  (bool).

  Ranking is Postgres weighted `tsvector`: a publication's findings (`text` +
  `quote`) sit in band **A**, its `title` in **B**, its `abstract` in **C** — so a
  term that appears **as a finding** outranks one that only appears in the
  title/abstract (`ts_rank_cd`). Matching is abstract-level (findings + title +
  abstract); full paper body is not indexed. Results are ordered by rank, then a
  `verified`-present tie-break (the label is a tie-break, **not** a score
  multiplier, so weak/contradicted matches stay visible), then the usual
  publication sort. A blank query returns no results (the caller treats blank as
  browse mode).
  """
  def search_condition_research(condition_id, query) do
    q = String.trim(query || "")

    if q == "" do
      %{results: [], result_count: 0}
    else
      ranked = ranked_pmids_for_condition(condition_id, q)
      rank_by_pmid = Map.new(ranked, fn r -> {r.pmid, r} end)
      pmids = Enum.map(ranked, & &1.pmid)

      results =
        case pmids do
          [] ->
            []

          _ ->
            facts =
              ConditionMinedFact
              |> where([f], f.condition_id == ^condition_id and f.pmid in ^pmids)
              |> Repo.all()

            studies = studies_by_pmid(facts)

            facts
            |> Enum.group_by(& &1.pmid)
            |> Enum.map(fn {pmid, pmid_facts} ->
              r = Map.get(rank_by_pmid, pmid, %{rank: 0.0, matched_in_finding: false})

              build_publication(pmid, pmid_facts, studies)
              |> Map.put(:rank, r.rank)
              |> Map.put(:matched_in_finding, r.matched_in_finding)
            end)
            |> Enum.sort_by(&search_result_sort_key/1)
        end

      %{results: results, result_count: length(results)}
    end
  end

  # Rank each matching PMID for a condition by a weighted tsvector document
  # (findings text+quote = A, title = B, abstract = C). One grouped query;
  # ordering happens in Elixir (small per-condition corpora) so the document
  # isn't repeated in an ORDER BY too. The `?::text = ?` join bridges the string
  # `f.pmid` to the integer `s.pmid`; an unenriched pmid gets a null study
  # (findings-only rank). The weighted document is inlined as a literal fragment
  # in both HAVING and SELECT (Ecto `fragment/1` needs a compile-time string).
  defp ranked_pmids_for_condition(condition_id, q) do
    ConditionMinedFact
    |> where([f], f.condition_id == ^condition_id)
    |> join(:left, [f], s in ScientificStudy, on: fragment("?::text = ?", s.pmid, f.pmid))
    |> group_by([f, s], [f.pmid, s.id, s.title, s.abstract])
    |> having(
      [f, s],
      fragment(
        "(setweight(to_tsvector('english', unaccent(coalesce(string_agg(?, ' '), ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(string_agg(coalesce(?, ''), ' '), ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'B') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'C')) @@ websearch_to_tsquery('english', unaccent(?))",
        f.text,
        f.quote,
        s.title,
        s.abstract,
        ^q
      )
    )
    |> select([f, s], %{
      pmid: f.pmid,
      rank:
        fragment(
          "ts_rank_cd((setweight(to_tsvector('english', unaccent(coalesce(string_agg(?, ' '), ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(string_agg(coalesce(?, ''), ' '), ''))), 'A') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'B') || setweight(to_tsvector('english', unaccent(coalesce(?, ''))), 'C')), websearch_to_tsquery('english', unaccent(?)))",
          f.text,
          f.quote,
          s.title,
          s.abstract,
          ^q
        ),
      matched_in_finding:
        fragment(
          "to_tsvector('english', unaccent(coalesce(string_agg(?, ' '), ''))) @@ websearch_to_tsquery('english', unaccent(?))",
          f.text,
          ^q
        )
    })
    |> Repo.all()
  end

  # Search result order: rank desc, then verified-present (tie-break only, never a
  # score multiplier so weak/contradicted matches stay visible), then the usual
  # MEDLINE→year→title publication sort.
  defp search_result_sort_key(pub) do
    has_verified = if Enum.any?(pub.facts, &(&1.label == "verified")), do: 0, else: 1
    {-(pub.rank || 0.0), has_verified, publication_sort_key(pub)}
  end

  @global_search_limit 50

  @doc """
  Global, cross-condition research search (Phase 2). Returns a ranked list of
  **one card per PMID**, each carrying the publication metadata plus the per-
  condition rows it's filed under:

      %{pmid, study_id, card_rank, any_in_finding, study, abstract_snippet,
        conditions: [%{condition_id, condition_name, label, finding_text, in_finding}]}

  Reads the `research_search` materialized view (findings=A, title=B, abstract=C):
  a finding-match outranks a title/abstract-only one, and **abstract-inclusive** —
  a paper surfaces on an abstract hit even when no finding mentions the term
  (`any_in_finding: false` → the card shows a "Matched in abstract" snippet). PMID
  dedupe is an exact `GROUP BY` (not entity resolution); every per-condition row
  keeps its own label (never collapsed to one "winning" label). Capped at
  #{@global_search_limit} cards. A blank query returns `[]`.
  """
  def search_all_research(query, _opts \\ []) do
    q = String.trim(query || "")

    if q == "" do
      []
    else
      rows = global_search_rows(q)

      pmids = Enum.map(rows, & &1.pmid)
      studies = studies_by_pmid_strings(pmids)

      Enum.map(rows, fn row ->
        study = Map.get(studies, row.pmid)

        %{
          pmid: row.pmid,
          study_id: row.study_id,
          card_rank: row.card_rank,
          any_in_finding: row.any_in_finding,
          conditions: normalize_condition_rows(row.conditions),
          study: study,
          # The abstract is why this card surfaced only when no finding matched.
          abstract_snippet: unless(row.any_in_finding, do: study && study.abstract)
        }
        |> Map.merge(study_meta(study))
      end)
    end
  end

  # Raw SQL: rank each MV row, keep the best finding per (pmid, condition), then
  # collapse to one card per PMID with a jsonb array of its per-condition rows
  # (verified-first inside the card). Card order = MAX(rank), finding-match as a
  # tie-break (label is displayed, never folded into the score).
  defp global_search_rows(q) do
    sql = """
    WITH tsq AS (SELECT websearch_to_tsquery('english', unaccent($1)) AS q),
    hits AS (
      SELECT rs.*, ts_rank_cd(rs.document, tsq.q) AS rank, (rs.finding_tsv @@ tsq.q) AS in_finding
      FROM research_search rs, tsq
      WHERE rs.document @@ tsq.q
    ),
    per_condition AS (
      SELECT DISTINCT ON (pmid, condition_id) *
      FROM hits
      ORDER BY pmid, condition_id, rank DESC
    )
    SELECT
      pmid,
      MAX(rank) AS card_rank,
      bool_or(in_finding) AS any_in_finding,
      (array_agg(study_id) FILTER (WHERE study_id IS NOT NULL))[1] AS study_id,
      jsonb_agg(
        jsonb_build_object(
          'condition_id', condition_id, 'condition_name', condition_name,
          'label', label, 'finding_text', finding_text, 'in_finding', in_finding
        )
        ORDER BY (label = 'verified') DESC, rank DESC
      ) AS conditions
    FROM per_condition
    GROUP BY pmid
    ORDER BY MAX(rank) DESC, bool_or(in_finding) DESC
    LIMIT #{@global_search_limit}
    """

    %{rows: rows} = Repo.query!(sql, [q])

    Enum.map(rows, fn [pmid, card_rank, any_in_finding, study_id, conditions] ->
      %{
        pmid: pmid,
        card_rank: card_rank,
        any_in_finding: any_in_finding,
        study_id: study_id,
        conditions: conditions
      }
    end)
  end

  # The jsonb array comes back with string keys; atomize to the render shape.
  defp normalize_condition_rows(conditions) when is_list(conditions) do
    Enum.map(conditions, fn c ->
      %{
        condition_id: c["condition_id"],
        condition_name: c["condition_name"],
        label: c["label"],
        finding_text: c["finding_text"],
        in_finding: c["in_finding"]
      }
    end)
  end

  defp normalize_condition_rows(_), do: []

  # Like `studies_by_pmid/1` but keyed off raw pmid strings (global rows carry no
  # fact structs). Reused for card display metadata.
  defp studies_by_pmid_strings(pmid_strings) do
    pmids =
      pmid_strings
      |> Enum.map(&parse_pmid/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case pmids do
      [] ->
        %{}

      _ ->
        ScientificStudy
        |> where([s], s.pmid in ^pmids)
        |> Repo.all()
        |> Map.new(fn s -> {to_string(s.pmid), s} end)
    end
  end

  @doc """
  Trigram spelling correction for the global search. For each whitespace token,
  finds the closest lexeme in the `research_search` corpus (`pg_trgm` similarity
  over `ts_stat`); returns the corrected query string when it differs from the
  input, else `nil`. Used to auto-retry a typo'd query (e.g. "mediteranean" →
  "mediterranean") that `websearch_to_tsquery` can't match on its own.
  """
  def spelling_suggestion(query) do
    tokens =
      (query || "")
      |> String.trim()
      |> String.split(~r/\s+/u, trim: true)

    case tokens do
      [] ->
        nil

      _ ->
        corrected = Enum.map(tokens, &closest_corpus_word/1)

        if Enum.map(corrected, &String.downcase/1) != Enum.map(tokens, &String.downcase/1) do
          Enum.join(corrected, " ")
        end
    end
  end

  # The corpus **surface word** most trigram-similar to `token` (≥ 0.4), else the
  # token unchanged. Built from the raw finding/title/abstract text (NOT `ts_stat`
  # lexemes — those are stemmed, e.g. "ulcerative"→"ulcer", so a typo like
  # "ulclerative" wouldn't match the stem). Only called when a search already
  # returned nothing, so the full-text scan is off the hot path.
  defp closest_corpus_word(token) do
    closest_word(token, """
    SELECT DISTINCT lower(w) AS word
    FROM condition_mined_facts f
    LEFT JOIN scientific_studies s ON s.pmid::text = f.pmid
    CROSS JOIN LATERAL regexp_split_to_table(
      coalesce(f.text, '') || ' ' || coalesce(s.title, '') || ' ' || coalesce(s.abstract, ''),
      '[^[:alpha:]]+'
    ) AS w
    WHERE length(w) >= 4
    """)
  end

  # The **surface word** in `vocab_sql` (a `SELECT … AS word` fragment) most
  # trigram-similar to `token` (≥ 0.4), else the token unchanged. Shared by the
  # global-corpus and condition-name spelling corrections — they differ only in
  # which vocabulary they scan.
  defp closest_word(token, vocab_sql) do
    sql = """
    SELECT word
    FROM (#{vocab_sql}) vocab
    WHERE similarity(word, $1) > 0.4
    ORDER BY similarity(word, $1) DESC
    LIMIT 1
    """

    case Repo.query!(sql, [token]) do
      %{rows: [[word]]} -> word
      _ -> token
    end
  end

  @doc """
  Rebuild the `research_search` materialized view (global search index). Called
  app-side after a condition mine commits — `REFRESH … CONCURRENTLY` must run
  outside a transaction, so this is NOT a DB trigger. Tolerant: logs and returns
  `:error` if the view can't be refreshed concurrently (e.g. never populated / a
  sandboxed transaction) rather than failing the mine.
  """
  def refresh_research_search do
    case Repo.query("REFRESH MATERIALIZED VIEW CONCURRENTLY research_search") do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("[FactMining] research_search refresh failed: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  The nutritionist research-search **landing list**: every `Health.Condition` with
  its distinct-publication `study_count` from mined facts (0 when none mined yet),
  research-first then by name. `search` is **tolerant** (parity with the global
  search): accent-insensitive, word-order-independent per-token matching over the
  condition's `name` **and** its `synonyms`. Mirrors the `%{condition, study_count}`
  shape of `Literature.conditions_for_search/1`. For typo auto-correction + a
  "showing results for…" banner, call `search_conditions/1` instead.
  """
  def conditions_for_search(search \\ nil) do
    Condition
    |> join(:left, [c], f in ConditionMinedFact, on: f.condition_id == c.id)
    |> filter_conditions(search)
    |> group_by([c], c.id)
    |> select([c, f], %{condition: c, study_count: count(f.pmid, :distinct)})
    |> order_by([c, f], desc: count(f.pmid, :distinct), asc: c.name)
    |> Repo.all()
  end

  @doc """
  The nutritionist research-search **landing search** — `conditions_for_search/1`
  with the same typo-correction retry the global search uses. Returns
  `%{entries, corrected}` where `corrected` is `{original, suggestion}` when a
  blank-result query was auto-retried with a trigram-corrected spelling (else
  `nil`). A blank query returns the full catalog, uncorrected.
  """
  def search_conditions(search) do
    trimmed = String.trim(search || "")
    entries = conditions_for_search(trimmed)

    cond do
      trimmed == "" ->
        %{entries: entries, corrected: nil}

      entries != [] ->
        %{entries: entries, corrected: nil}

      true ->
        case condition_spelling_suggestion(trimmed) do
          nil -> %{entries: [], corrected: nil}
          sugg -> %{entries: conditions_for_search(sugg), corrected: {trimmed, sugg}}
        end
    end
  end

  @doc "How many distinct conditions have at least one mined fact."
  def count_conditions_with_mined_facts do
    ConditionMinedFact
    |> select([f], count(f.condition_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  # Tolerant condition filter: each whitespace token must match (AND — order
  # independent) either the unaccented `name` or any unaccented `synonym` as a
  # substring. Blank → identity (full catalog).
  defp filter_conditions(query, search) when is_binary(search) do
    search
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reduce(query, fn tok, q ->
      like = "%#{tok}%"

      where(
        q,
        [c],
        fragment("unaccent(?) ILIKE unaccent(?)", c.name, ^like) or
          fragment(
            "EXISTS (SELECT 1 FROM unnest(?) s WHERE unaccent(s) ILIKE unaccent(?))",
            c.synonyms,
            ^like
          )
      )
    end)
  end

  defp filter_conditions(query, _search), do: query

  @doc """
  Trigram spelling correction for the condition search. Same per-token shape as
  `spelling_suggestion/1`, but the vocabulary is the condition **names + synonyms**
  (not the facts corpus) — the ~150 conditions with no mined facts never appear in
  the facts corpus, so only the labels themselves can correct a typo'd name.
  """
  def condition_spelling_suggestion(query) do
    tokens =
      (query || "")
      |> String.trim()
      |> String.split(~r/\s+/u, trim: true)

    case tokens do
      [] ->
        nil

      _ ->
        corrected = Enum.map(tokens, &closest_condition_word/1)

        if Enum.map(corrected, &String.downcase/1) != Enum.map(tokens, &String.downcase/1) do
          Enum.join(corrected, " ")
        end
    end
  end

  # The condition-label surface word most trigram-similar to `token` (≥ 0.4),
  # else the token unchanged — vocabulary is every word in `conditions.name` +
  # `conditions.synonyms`.
  defp closest_condition_word(token) do
    closest_word(token, """
    SELECT DISTINCT lower(w) AS word
    FROM conditions c
    CROSS JOIN LATERAL regexp_split_to_table(
      c.name || ' ' || coalesce(array_to_string(c.synonyms, ' '), ''),
      '[^[:alpha:]]+'
    ) AS w
    WHERE length(w) >= 4
    """)
  end

  defp studies_by_pmid(facts) do
    pmids =
      facts
      |> Enum.map(&parse_pmid(&1.pmid))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case pmids do
      [] ->
        %{}

      _ ->
        ScientificStudy
        |> where([s], s.pmid in ^pmids)
        |> Repo.all()
        |> Map.new(fn s -> {to_string(s.pmid), s} end)
    end
  end

  defp build_publication(pmid, facts, studies) do
    study = pmid && Map.get(studies, to_string(pmid))
    rep = representative_fact(facts)

    Map.merge(
      %{
        pmid: pmid,
        pmcid: rep && rep.pmcid,
        doi: rep && rep.doi,
        study: study,
        bucket: ResearchType.bucket(rep && rep.study_design),
        presentable?: Enum.any?(facts, &(&1.license == "commercial_ok")),
        facts: Enum.sort_by(facts, &label_rank(&1.label))
      },
      study_meta(study)
    )
  end

  # Publication-card metadata from the enriched ScientificStudy (nil-safe defaults).
  defp study_meta(%ScientificStudy{} = study) do
    %{
      study_id: study.id,
      title: study.title,
      journal: study.journal,
      authors: study.authors || [],
      publication_year: publication_year(study),
      medline?: JournalAuthority.medline_indexed?(study)
    }
  end

  defp study_meta(_absent) do
    %{
      study_id: nil,
      title: nil,
      journal: nil,
      authors: [],
      publication_year: nil,
      medline?: false
    }
  end

  # The fact whose study design sits highest in the evidence pyramid represents
  # the publication (its pmcid/doi/design drive the card + its research-type group).
  defp representative_fact(facts) do
    Enum.min_by(facts, &ResearchType.order(ResearchType.bucket(&1.study_design)), fn -> nil end)
  end

  defp publication_sort_key(pub) do
    {if(pub.medline?, do: 0, else: 1), -(pub.publication_year || -99_999), pub.title || ""}
  end

  defp label_rank(label), do: Map.get(@label_order, label, 9)

  defp parse_pmid(pmid) when is_integer(pmid), do: pmid

  defp parse_pmid(pmid) when is_binary(pmid) do
    case Integer.parse(pmid) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_pmid(_), do: nil

  defp publication_year(%ScientificStudy{publication_date: %Date{year: year}}), do: year

  defp publication_year(%ScientificStudy{publication_date: date}) when is_binary(date) do
    case Integer.parse(date) do
      {year, _} when year > 1000 -> year
      _ -> nil
    end
  end

  defp publication_year(_), do: nil
end
