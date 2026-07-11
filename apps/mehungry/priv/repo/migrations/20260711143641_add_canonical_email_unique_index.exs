defmodule Mehungry.Repo.Migrations.AddCanonicalEmailUniqueIndex do
  use Ecto.Migration

  require Logger

  # Self-healing: existing Gmail-alias duplicates would make the unique index
  # creation fail, so we delete them first (keep the oldest account per inbox)
  # via Accounts.dedupe_alias_accounts/1. To preview what will be removed before
  # deploying, run `mix mehungry.dedupe_aliases` (dry run) against the target DB.
  def up do
    result = Mehungry.Accounts.dedupe_alias_accounts(dry_run: false)

    Logger.info(
      "[AddCanonicalEmailUniqueIndex] deduped #{length(result.deleted)} alias account(s) " <>
        "across #{result.clusters} inbox cluster(s) before indexing"
    )

    create unique_index(:users, [:canonical_email])
  end

  def down do
    drop unique_index(:users, [:canonical_email])
  end
end
