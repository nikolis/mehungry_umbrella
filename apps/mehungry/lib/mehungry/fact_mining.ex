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
  """
  def mine_species(%FoundementalFoodSpecies{} = species) do
    query = query_for_species(species)

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

  def mine_species(species_id) when is_integer(species_id) do
    mine_species(Food.get_foundemental_species!(species_id))
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
  """
  def mine_condition(%Condition{} = condition) do
    query = query_for_condition(condition)

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

  def mine_condition(condition_id) when is_integer(condition_id) do
    mine_condition(Health.get_condition!(condition_id))
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
      %{
        owner_field => owner_id,
        label: label,
        certainty: verdict["certainty"],
        reason: verdict["reason"],
        conflicting_pmid: verdict["conflicting_pmid"],
        assessment: verdict["assessment"],
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
  The nutritionist research-search **landing list**: every `Health.Condition` with
  its distinct-publication `study_count` from mined facts (0 when none mined yet),
  research-first then by name. `search` applies a simple name `ILIKE` filter.
  Mirrors the `%{condition, study_count}` shape of `Literature.conditions_for_search/1`.
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

  @doc "How many distinct conditions have at least one mined fact."
  def count_conditions_with_mined_facts do
    ConditionMinedFact
    |> select([f], count(f.condition_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp filter_conditions(query, search) when is_binary(search) do
    case String.trim(search) do
      "" -> query
      term -> where(query, [c], ilike(c.name, ^"%#{term}%"))
    end
  end

  defp filter_conditions(query, _search), do: query

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
    %{study_id: nil, title: nil, journal: nil, authors: [], publication_year: nil, medline?: false}
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
