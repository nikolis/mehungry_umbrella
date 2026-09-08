defmodule Mehungry.Professionals.DietaryHistory.Importer do
  @moduledoc """
  Imports a parsed dietary-history CSV into a new `ProfessionalClient` with its
  `ClientIntake` and `ConsultationNote`s, all owned by a professional.

  Parsing is delegated to `DietaryHistory.CsvParser`; this module owns the IO
  (file read) and the DB write (a single `Ecto.Multi`).
  """

  alias Mehungry.Repo
  alias Mehungry.Professionals.{ProfessionalClient, ClientIntake, ConsultationNote}
  alias Mehungry.Professionals.DietaryHistory.CsvParser

  # Exported sheets sometimes have the identity rows blank; the client record
  # still needs a name.
  @default_name "Νέος πελάτης"

  @doc """
  Imports CSV content under `professional_id`.

  Options:
    * `:full_name` — overrides/falls back for the client name when the sheet's
      ΟΝΟΜΑΤΕΠΩΝΥΜΟ row is blank.

  Returns `{:ok, %{client: client, notes_count: n}}` or
  `{:error, step, changeset_or_reason, changes_so_far}` / `{:error, reason}`.
  """
  def import_csv(professional_id, content, opts \\ []) when is_binary(content) do
    with {:ok, parsed} <- CsvParser.parse(content) do
      insert_all(professional_id, parsed, opts)
    end
  end

  @doc "Reads a CSV file and imports it. See `import_csv/3`."
  def import_file(professional_id, path, opts \\ []) do
    case File.read(path) do
      {:ok, content} -> import_csv(professional_id, content, opts)
      {:error, reason} -> {:error, {:file_read, reason}}
    end
  end

  defp insert_all(professional_id, parsed, opts) do
    client_attrs =
      parsed.client
      |> Map.put(:professional_id, professional_id)
      |> Map.put_new(:full_name, nil)
      |> ensure_name(opts)

    intake_attrs = parsed.intake
    note_attrs_list = parsed.consultation_notes

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :client,
        ProfessionalClient.changeset(%ProfessionalClient{}, client_attrs)
      )
      |> Ecto.Multi.insert(:intake, fn %{client: client} ->
        ClientIntake.changeset(
          %ClientIntake{},
          Map.put(intake_attrs, :professional_client_id, client.id)
        )
      end)
      |> Ecto.Multi.run(:notes, fn repo, %{client: client} ->
        notes =
          Enum.map(note_attrs_list, fn attrs ->
            repo.insert!(
              ConsultationNote.changeset(
                %ConsultationNote{},
                Map.put(attrs, :professional_client_id, client.id)
              )
            )
          end)

        {:ok, notes}
      end)

    case Repo.transaction(multi) do
      {:ok, %{client: client, notes: notes}} ->
        {:ok, %{client: client, notes_count: length(notes)}}

      {:error, step, reason, changes} ->
        {:error, step, reason, changes}
    end
  end

  defp ensure_name(%{full_name: name} = attrs, opts) do
    resolved =
      cond do
        is_binary(name) and String.trim(name) != "" -> name
        is_binary(opts[:full_name]) and String.trim(opts[:full_name]) != "" -> opts[:full_name]
        true -> @default_name
      end

    Map.put(attrs, :full_name, resolved)
  end
end
