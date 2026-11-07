defmodule Mehungry.Progress.PhotoMigration do
  @moduledoc """
  One-off sweep moving legacy progress-photo objects out of the **public**
  media bucket into the **private** bucket, then clearing each row's
  world-readable `url` so all reads go through signed URLs
  (`Mehungry.Progress.photo_url/1`).

  Per photo row still carrying a public `url`:

    1. copy the object (same `storage_key`) public → private
    2. delete the public original
    3. update the row: keep `storage_key`, set `url: nil`

  Idempotent — rows with `url: nil` are already private and are skipped, so a
  crashed run can simply be re-run. Note: deleted public URLs may linger in
  Supabase's CDN cache for a short while.

  Dev: `mix progress.migrate_photos [--dry-run]`.
  Prod (release has no Mix):

      fly ssh console -C '/app/bin/mehungry_umbrella eval "Mehungry.Progress.PhotoMigration.run()"'
  """

  import Ecto.Query

  alias Mehungry.Progress.Photo
  alias Mehungry.Repo
  alias Mehungry.Storage

  def run(opts \\ []) do
    {:ok, _} = Application.ensure_all_started(:mehungry)
    dry_run = Keyword.get(opts, :dry_run, false)

    photos = Repo.all(from ph in Photo, where: not is_nil(ph.url), order_by: ph.id)
    log("#{length(photos)} public-bucket photo(s) to migrate#{if dry_run, do: " (dry run)"}")

    results = Enum.map(photos, &migrate_photo(&1, dry_run))
    ok = Enum.count(results, &(&1 == :ok))
    log("done: #{ok} migrated, #{length(results) - ok} failed")

    results
  end

  defp migrate_photo(%Photo{} = photo, dry_run) do
    key = photo.storage_key || Storage.key_from_url(photo.url)

    cond do
      is_nil(key) ->
        log("photo #{photo.id}: no storage key derivable from #{inspect(photo.url)} — skipped")
        :error

      dry_run ->
        log("photo #{photo.id}: would move #{key} → private")
        :ok

      true ->
        with {:ok, binary} <- Storage.get(key),
             {:ok, _} <-
               Storage.put(key, binary, content_type: content_type(key), bucket: :private) do
          # Best-effort: a failed public delete leaves a stray public object,
          # not a broken row — safe to re-delete by hand.
          Storage.delete(key)

          photo
          |> Ecto.Changeset.change(storage_key: key, url: nil)
          |> Repo.update!()

          log("photo #{photo.id}: #{key} → private")
          :ok
        else
          {:error, reason} ->
            log("photo #{photo.id}: FAILED (#{inspect(reason)}) — left on the public bucket")
            :error
        end
    end
  end

  # The private bucket enforces allowed_mime_types, so the copy must carry the
  # real image content type (derived from the key's extension).
  defp content_type(key) do
    case key |> Path.extname() |> String.downcase() do
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      ".heic" -> "image/heic"
      _ -> "image/jpeg"
    end
  end

  defp log(msg), do: IO.puts("[progress photo migration] #{msg}")
end
