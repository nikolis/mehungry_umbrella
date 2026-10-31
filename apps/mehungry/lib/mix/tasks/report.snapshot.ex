defmodule Mix.Tasks.Report.Snapshot do
  @shortdoc "Pulls the weekly app-status snapshot (DB + GA4 + Facebook + Pinterest)"

  @moduledoc """
  Gathers the `docs/implementation/app_status.md` weekly snapshot from all four §7 sources in
  one pass and prints a human-readable report ending with a ready-to-paste §6
  table row.

      mix report.snapshot            # last 28 days (GA4/Pinterest window)
      mix report.snapshot --days 7
      mix report.snapshot --row      # print only the §6 log row

  Degrades gracefully: GA4/Facebook/Pinterest sections show a clear
  "not configured" note when their credential/scope/env is missing, so the DB
  figures always print. Optional env vars (see `docs/implementation/app_status.md` §7):

    * `REPORT_RO_DATABASE_URL` — read through a read-only DB role (else the app Repo)
    * `GA4_SA_KEY`, `GA4_PROPERTY_ID` — enable the GA4 pull
    * `PINTEREST_ENV=live` — required for real Pinterest analytics
  """

  use Mix.Task

  alias Mehungry.Report.Snapshot

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [days: :integer, row: :boolean])

    snapshot = Snapshot.gather(days: Keyword.get(opts, :days, 28))

    output =
      if Keyword.get(opts, :row, false),
        do: Snapshot.to_log_row(snapshot),
        else: Snapshot.to_report(snapshot)

    Mix.shell().info(output)
  end
end
