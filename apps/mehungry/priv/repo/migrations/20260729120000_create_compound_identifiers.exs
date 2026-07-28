defmodule Mehungry.Repo.Migrations.CreateCompoundIdentifiers do
  use Ecto.Migration

  # Normalized cross-database identifier model for the compound registry.
  #
  # Identifiers — not names — are the stable currency for integrating heterogeneous
  # scientific data, so every external identity (MeSH, PubChem CID, ChEBI, CAS,
  # HMDB, Wikidata, InChIKey) becomes a row in `compound_identifiers` with its own
  # namespace. Adopting a new chemical database never again requires a schema
  # change, and `Mehungry.Chemistry.Resolver` can look a compound up uniformly by
  # any identifier.
  #
  # The scalar identity columns on `compounds` (`pubchem_cid`, `chebi_id`, and the
  # `identifiers` jsonb) are therefore removed. Structural *descriptors* that are
  # not globally-unique identifiers (molecular formula, IUPAC name, SMILES, InChI)
  # cannot live in a `(namespace, identifier)`-unique table — isomers share a
  # formula — so they move to a new `properties` jsonb on `compounds`.
  #
  # These migrations are undeployed (this feature branch only); the backfill keeps
  # any dev/seed rows intact.
  def up do
    # ── 1. Normalized identifier table ───────────────────────────────────────
    create table(:compound_identifiers) do
      add :compound_id, references(:compounds, on_delete: :delete_all), null: false
      # mesh | pubchem | chebi | cas | hmdb | wikidata | inchikey | foodb ...
      add :namespace, :string, null: false
      add :identifier, :string, null: false
      # The identity this compound was seeded from (e.g. the MeSH id from PubTator).
      add :is_primary, :boolean, null: false, default: false
      # Who asserted this identifier: pubchem | pubtator | chemistry | manual ...
      add :source, :string

      timestamps()
    end

    # One compound per external id — replaces the old partial-unique pubchem_cid.
    create unique_index(:compound_identifiers, [:namespace, :identifier])
    create index(:compound_identifiers, [:compound_id])

    # ── 2. Structural descriptors move off the scalar columns ────────────────
    alter table(:compounds) do
      add :properties, :map, default: %{}, null: false
    end

    # ── 3. Backfill dev/seed rows into the new model ─────────────────────────
    execute """
    INSERT INTO compound_identifiers (compound_id, namespace, identifier, is_primary, source, inserted_at, updated_at)
    SELECT id, 'pubchem', pubchem_cid::text, true, 'pubchem', now(), now()
    FROM compounds WHERE pubchem_cid IS NOT NULL
    """

    execute """
    INSERT INTO compound_identifiers (compound_id, namespace, identifier, is_primary, source, inserted_at, updated_at)
    SELECT id, 'chebi', chebi_id, false, 'pubchem', now(), now()
    FROM compounds WHERE chebi_id IS NOT NULL AND chebi_id <> ''
    """

    execute """
    INSERT INTO compound_identifiers (compound_id, namespace, identifier, is_primary, source, inserted_at, updated_at)
    SELECT id, 'cas', identifiers->>'cas_number', false, 'legacy', now(), now()
    FROM compounds WHERE identifiers->>'cas_number' IS NOT NULL
    """

    execute """
    INSERT INTO compound_identifiers (compound_id, namespace, identifier, is_primary, source, inserted_at, updated_at)
    SELECT id, 'inchikey', identifiers->>'inchikey', false, 'legacy', now(), now()
    FROM compounds WHERE identifiers->>'inchikey' IS NOT NULL
    """

    execute """
    INSERT INTO compound_identifiers (compound_id, namespace, identifier, is_primary, source, inserted_at, updated_at)
    SELECT id, 'foodb', identifiers->>'foodb_id', false, 'legacy', now(), now()
    FROM compounds WHERE identifiers->>'foodb_id' IS NOT NULL
    """

    # Keep the structural descriptors (drop the keys promoted to identifier rows).
    execute """
    UPDATE compounds
    SET properties = COALESCE(identifiers, '{}'::jsonb) - 'cas_number' - 'inchikey' - 'foodb_id'
    """

    # ── 4. Drop the scalar identity columns ──────────────────────────────────
    drop unique_index(:compounds, [:pubchem_cid], where: "pubchem_cid IS NOT NULL")

    alter table(:compounds) do
      remove :pubchem_cid
      remove :chebi_id
      remove :identifiers
    end
  end

  def down do
    alter table(:compounds) do
      add :pubchem_cid, :integer
      add :chebi_id, :string
      add :identifiers, :map, default: %{}, null: false
    end

    create unique_index(:compounds, [:pubchem_cid], where: "pubchem_cid IS NOT NULL")

    # Best-effort restore of the scalar identity from the normalized rows.
    execute """
    UPDATE compounds c
    SET pubchem_cid = ci.identifier::integer
    FROM compound_identifiers ci
    WHERE ci.compound_id = c.id AND ci.namespace = 'pubchem'
    """

    execute """
    UPDATE compounds c
    SET chebi_id = ci.identifier
    FROM compound_identifiers ci
    WHERE ci.compound_id = c.id AND ci.namespace = 'chebi'
    """

    execute "UPDATE compounds SET identifiers = COALESCE(properties, '{}'::jsonb)"

    alter table(:compounds) do
      remove :properties
    end

    drop table(:compound_identifiers)
  end
end
