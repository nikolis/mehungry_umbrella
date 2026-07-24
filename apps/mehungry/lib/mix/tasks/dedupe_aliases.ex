defmodule Mix.Tasks.Mehungry.DedupeAliases do
  @shortdoc "Detects/deletes Gmail-alias duplicate accounts (keeps oldest per inbox)"

  @moduledoc """
  Finds accounts that share a canonical email (e.g. Gmail dot/`+tag` aliases that
  all reach one inbox) and, for each cluster, keeps the oldest account and
  deletes the rest via `Mehungry.Accounts.delete_user/1`.

  By default this is a **dry run** — it only reports what it would delete.

      mix mehungry.dedupe_aliases            # dry run (no changes)
      mix mehungry.dedupe_aliases --execute  # actually delete duplicates

  Run this AFTER the add_canonical_email migration has backfilled the column and
  BEFORE the unique-index migration.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [execute: :boolean])
    dry_run = not Keyword.get(opts, :execute, false)

    result = Mehungry.Accounts.dedupe_alias_accounts(dry_run: dry_run)

    shell = Mix.shell()

    shell.info("Alias clusters found (>1 account per inbox): #{result.clusters}")
    shell.info("Accounts to keep (oldest per inbox):        #{length(result.kept)}")

    shell.info(
      "Accounts #{if dry_run, do: "that WOULD be", else: "DELETED"}: #{length(result.deleted)}"
    )

    Enum.each(result.deleted, fn %{id: id, email: email, canonical_email: canonical} ->
      shell.info("  - id=#{id} #{email} -> #{canonical}")
    end)

    if dry_run and result.deleted != [] do
      shell.info("\nDry run only. Re-run with --execute to delete the accounts above.")
    end
  end
end
