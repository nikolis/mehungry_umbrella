defmodule Mehungry.Food.IdentityResolution do
  @moduledoc """
  Scientific Identity Resolution over the USDA-backed ingredient pool.

  Maps existing ingredients to external scientific identifiers — scientific name,
  NCBI taxonomy id, FoodOn id, Wikidata id, and synonyms — as *candidate*
  mappings. Design guarantees:

    * **Never overwrites.** Writes are find-or-create on natural keys; re-running
      resolution adds nothing new for an already-resolved (ingredient, name, source).
    * **Preserves history.** Rows are append-only; verifying a new identity marks
      the previously-verified one `superseded` (chained via `superseded_by_id`)
      rather than deleting it.
    * **Multiple candidates** per ingredient, each with `confidence` and
      `source`/`id_source` provenance.
    * **Manual verification workflow** — `verify_identity/2`, `reject_identity/2`.

  Resolution is orchestrated by `resolve_ingredient/1`, driven in bulk by
  `Mehungry.ObanWorkers.IngredientIdentityResolutionWorker` with progress tracked
  in `IdentityResolutionRuns`. The USDA scientific name and the external
  identifiers come from swappable source seams (`:usda_scientific_source`,
  `:scientific_id_client`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Ingredient,
    IngredientScientificIdentity,
    IngredientIdentitySynonym,
    IngredientIdentityResolutionAttempt
  }

  alias Mehungry.Food.IdentityResolution.{UsdaScientificSource, ExternalScientificIdClient}

  @usda_source_name "usda_fdc"
  # A USDA-provided binomial is high-trust; external ids inherit it as a default.
  @default_confidence 0.9

  # ── Candidate identities (never-overwrite writes) ────────────────────────

  @doc """
  Find-or-create a candidate identity on the natural key
  `(ingredient_id, scientific_name, source)`. Returns `{:ok, identity, :created}`
  or `{:ok, identity, :exists}` — an existing mapping is never modified.
  """
  def add_identity_candidate(attrs) do
    attrs = Map.new(attrs)

    case get_identity_by_natural_key(attrs) do
      %IngredientScientificIdentity{} = existing ->
        {:ok, existing, :exists}

      nil ->
        case %IngredientScientificIdentity{}
             |> IngredientScientificIdentity.changeset(attrs)
             |> Repo.insert() do
          {:ok, identity} ->
            {:ok, identity, :created}

          # Lost an insert race on the unique index — fetch the winner.
          {:error, _changeset} ->
            {:ok, get_identity_by_natural_key(attrs), :exists}
        end
    end
  end

  defp get_identity_by_natural_key(attrs) do
    Repo.get_by(IngredientScientificIdentity,
      ingredient_id: attrs[:ingredient_id] || attrs["ingredient_id"],
      scientific_name: attrs[:scientific_name] || attrs["scientific_name"],
      source: attrs[:source] || attrs["source"]
    )
  end

  def get_identity!(id), do: Repo.get!(IngredientScientificIdentity, id)

  @doc "All identities for an ingredient, verified first, then by confidence."
  def list_identities(ingredient_id) do
    Repo.all(
      from(x in IngredientScientificIdentity,
        where: x.ingredient_id == ^ingredient_id,
        order_by: [
          desc:
            fragment(
              "case ? when 'verified' then 3 when 'candidate' then 2 when 'superseded' then 1 else 0 end",
              x.status
            ),
          desc_nulls_last: x.confidence,
          desc: x.id
        ]
      )
    )
  end

  @doc "The single verified identity for an ingredient, or nil."
  def verified_identity(ingredient_id) do
    Repo.one(
      from(x in IngredientScientificIdentity,
        where: x.ingredient_id == ^ingredient_id and x.status == "verified",
        limit: 1
      )
    )
  end

  # ── Synonyms (per identity, never-overwrite) ─────────────────────────────

  def add_synonym(attrs) do
    %IngredientIdentitySynonym{}
    |> IngredientIdentitySynonym.changeset(Map.new(attrs))
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:scientific_identity_id, :name, :synonym_type]
    )
  end

  def list_synonyms(scientific_identity_id) do
    Repo.all(
      from(s in IngredientIdentitySynonym,
        where: s.scientific_identity_id == ^scientific_identity_id,
        order_by: [asc: s.name]
      )
    )
  end

  @doc "All synonyms across every identity of an ingredient."
  def list_synonyms_for_ingredient(ingredient_id) do
    Repo.all(
      from(s in IngredientIdentitySynonym,
        join: x in IngredientScientificIdentity,
        on: x.id == s.scientific_identity_id,
        where: x.ingredient_id == ^ingredient_id,
        order_by: [asc: s.name]
      )
    )
  end

  # ── Manual verification workflow (history-preserving) ────────────────────

  @doc """
  Marks an identity `verified`. Any identity currently `verified` for the same
  ingredient is first marked `superseded` and pointed at the newly-verified one
  (never deleted), so history is preserved and the one-verified-per-ingredient
  partial unique index holds. Runs in a single transaction.
  """
  def verify_identity(identity_id, user_id \\ nil) do
    Repo.transaction(fn ->
      identity = Repo.get!(IngredientScientificIdentity, identity_id)

      from(x in IngredientScientificIdentity,
        where:
          x.ingredient_id == ^identity.ingredient_id and x.status == "verified" and
            x.id != ^identity_id
      )
      |> Repo.update_all(
        set: [status: "superseded", superseded_by_id: identity_id, updated_at: now()]
      )

      {:ok, verified} =
        identity
        |> IngredientScientificIdentity.changeset(%{
          status: "verified",
          verified_by_user_id: user_id,
          verified_at: now()
        })
        |> Repo.update()

      verified
    end)
  end

  @doc "Marks an identity `rejected` (kept for history)."
  def reject_identity(identity_id, _user_id \\ nil) do
    IngredientScientificIdentity
    |> Repo.get!(identity_id)
    |> IngredientScientificIdentity.changeset(%{status: "rejected"})
    |> Repo.update()
  end

  @doc "Unreviewed (candidate) identities, lowest-confidence first, ingredient preloaded."
  def list_pending_verification(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(x in IngredientScientificIdentity,
        where: x.status == "candidate",
        order_by: [asc_nulls_first: x.confidence, asc: x.id],
        preload: [:ingredient],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  # Attempt outcomes that produced no identity — an fdc-backed ingredient was
  # processed but yielded nothing to review. `matched` is excluded (it becomes a
  # candidate in `list_pending_verification/1`).
  @skipped_outcomes ~w(no_scientific_name error)

  @doc """
  Resolution attempts that produced **no** identity — the "skipped" ingredients —
  most recently attempted first, with `:ingredient` preloaded. Read-only review;
  `outcome` says which reason and `detail` carries the specifics.
  """
  def list_skipped_resolutions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(a in IngredientIdentityResolutionAttempt,
        where: a.outcome in @skipped_outcomes,
        order_by: [desc: a.attempted_at, desc: a.id],
        preload: [:ingredient],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  # ── Resolution ledger + progress ─────────────────────────────────────────

  @doc "Upserts the per-ingredient attempt row for `source` (defaults to usda_fdc)."
  def record_attempt(ingredient_id, outcome, detail \\ nil, source \\ @usda_source_name) do
    %IngredientIdentityResolutionAttempt{}
    |> IngredientIdentityResolutionAttempt.changeset(%{
      ingredient_id: ingredient_id,
      source: source,
      outcome: outcome,
      detail: detail,
      attempted_at: now()
    })
    |> Repo.insert(
      on_conflict: {:replace, [:outcome, :detail, :attempted_at, :updated_at]},
      conflict_target: [:ingredient_id, :source]
    )
  end

  @doc """
  Coverage snapshot `%{resolved: n, total: m}` for the progress bar. `resolved` is
  the number of fdc-backed ingredients that have been processed (have an attempt);
  `total` is all fdc-backed ingredients.
  """
  def resolution_progress do
    total =
      from(i in Ingredient, where: not is_nil(i.fdc_id) and i.fdc_id > 0)
      |> Repo.aggregate(:count)

    resolved =
      from(a in IngredientIdentityResolutionAttempt,
        join: i in Ingredient,
        on: i.id == a.ingredient_id,
        where: not is_nil(i.fdc_id) and i.fdc_id > 0,
        select: count(a.ingredient_id, :distinct)
      )
      |> Repo.one()

    %{resolved: resolved, total: total}
  end

  @doc "A batch of fdc-backed ingredients not yet attempted for `usda_fdc`, newest first."
  def list_unresolved_ingredients(limit) do
    Repo.all(
      from(i in Ingredient,
        left_join: a in IngredientIdentityResolutionAttempt,
        on: a.ingredient_id == i.id and a.source == @usda_source_name,
        where: not is_nil(i.fdc_id) and i.fdc_id > 0 and is_nil(a.id),
        order_by: [desc: i.id],
        limit: ^limit
      )
    )
  end

  # ── Orchestration ────────────────────────────────────────────────────────

  @doc """
  Resolves one ingredient: fetch the USDA scientific name, enrich with external
  identifiers, insert a candidate identity (+ synonyms), and record the attempt.

  Returns `{:ok, :matched | :no_scientific_name | :error}` — always advances, an
  attempt is recorded — or `{:error, reason}` for a transient failure (rate-limit
  or network) that the batch worker should let Oban retry (no attempt recorded).
  """
  def resolve_ingredient(%Ingredient{fdc_id: fdc_id}) when is_nil(fdc_id) or fdc_id <= 0,
    do: {:ok, :no_scientific_name}

  def resolve_ingredient(%Ingredient{id: id, fdc_id: fdc_id}) do
    case usda_source().fetch_scientific_name(fdc_id) do
      {:ok, %{scientific_name: nil}, _meta} ->
        record_attempt(id, "no_scientific_name")
        {:ok, :no_scientific_name}

      {:ok, %{scientific_name: scientific_name} = usda, _meta} ->
        insert_resolution(id, scientific_name, usda)
        record_attempt(id, "matched", scientific_name)
        {:ok, :matched}

      # Transient — let Oban retry the batch; the ledger makes the retry idempotent.
      {:error, {:rate_limited, _} = reason} ->
        {:error, reason}

      {:error, {:network, _} = reason} ->
        {:error, reason}

      # Definitive per-row failure (404, no key, decode) — record and advance so
      # one bad ingredient can't stall the whole run.
      {:error, reason} ->
        record_attempt(id, "error", inspect(reason))
        {:ok, :error}
    end
  end

  defp insert_resolution(ingredient_id, scientific_name, usda) do
    ids = fetch_external_ids(scientific_name)

    {:ok, identity, _} =
      add_identity_candidate(%{
        ingredient_id: ingredient_id,
        scientific_name: scientific_name,
        rank: ids[:rank],
        ncbi_taxonomy_id: ids[:ncbi_taxonomy_id],
        foodon_id: ids[:foodon_id],
        wikidata_id: ids[:wikidata_id],
        source: @usda_source_name,
        id_source: ids[:id_source],
        confidence: @default_confidence,
        status: "candidate",
        notes: usda[:description]
      })

    for synonym <- ids[:synonyms] || [] do
      add_synonym(Map.put(synonym, :scientific_identity_id, identity.id))
    end

    identity
  end

  # External id lookups never fail a resolution — a client error yields no ids.
  defp fetch_external_ids(scientific_name) do
    case id_client().resolve(scientific_name) do
      {:ok, ids} when is_map(ids) -> ids
      _ -> %{}
    end
  end

  # ── Enqueue ──────────────────────────────────────────────────────────────

  @doc "Opens a tracked run and enqueues the first resolution batch."
  def enqueue_resolution do
    run = Mehungry.Food.IdentityResolutionRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.IngredientIdentityResolutionWorker.new()
      |> Oban.insert()

    {:ok, run}
  end

  # ── Seams ────────────────────────────────────────────────────────────────

  defp usda_source do
    Application.get_env(:mehungry, :usda_scientific_source, UsdaScientificSource)
  end

  defp id_client do
    Application.get_env(:mehungry, :scientific_id_client, ExternalScientificIdClient)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
