defmodule Mix.Tasks.Progress.MigratePhotos do
  @shortdoc "One-off: move progress photos from the public bucket to the private one"

  @moduledoc """
  Dev wrapper around `Mehungry.Progress.PhotoMigration` (see that module —
  in prod, where the release has no Mix, call it via `eval`).

      mix progress.migrate_photos [--dry-run]
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Mehungry.Progress.PhotoMigration.run(dry_run: "--dry-run" in args)
  end
end
