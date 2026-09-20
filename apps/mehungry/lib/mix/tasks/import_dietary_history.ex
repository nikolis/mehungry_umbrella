defmodule Mix.Tasks.Import.DietaryHistory do
  @shortdoc "Imports a nutritionist dietary-history CSV export into a client record"

  @moduledoc """
  Parses a "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" Google-Sheet CSV export and inserts a
  `ProfessionalClient` with its intake and consultation notes, owned by the
  professional resolved from `--professional-email` and anchored to the platform
  user resolved from `--client-email` (a record is never headless).

      mix import.dietary_history --path FILE.csv --professional-email nutri@example.com --client-email client@example.com
      mix import.dietary_history --path FILE.csv --professional-email nutri@example.com --client-email client@example.com --name "Maria K."

  `--name` supplies/overrides the client name when the sheet's identity row is blank.
  """

  use Mix.Task

  alias Mehungry.Accounts
  alias Mehungry.Professionals.DietaryHistory.Importer

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          path: :string,
          professional_email: :string,
          client_email: :string,
          name: :string
        ]
      )

    path = opts[:path] || Mix.raise("--path is required")
    email = opts[:professional_email] || Mix.raise("--professional-email is required")
    client_email = opts[:client_email] || Mix.raise("--client-email is required")

    professional =
      Accounts.get_user_by_email(email) ||
        Mix.raise("No user found for email #{email}")

    client_user =
      Accounts.get_user_by_email(client_email) ||
        Mix.raise("No user found for client email #{client_email}")

    import_opts =
      [user_id: client_user.id] ++ if opts[:name], do: [full_name: opts[:name]], else: []

    case Importer.import_file(professional.id, path, import_opts) do
      {:ok, %{client: client, notes_count: n}} ->
        Mix.shell().info(
          "Imported client ##{client.id} (#{client.full_name}) with #{n} consultation notes."
        )

      {:error, step, reason, _changes} ->
        Mix.raise("Import failed at #{inspect(step)}: #{inspect(reason)}")

      {:error, reason} ->
        Mix.raise("Import failed: #{inspect(reason)}")
    end
  end
end
