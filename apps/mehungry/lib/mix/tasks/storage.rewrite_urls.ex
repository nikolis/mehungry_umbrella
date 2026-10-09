defmodule Mix.Tasks.Storage.RewriteUrls do
  @shortdoc "Rewrite stored S3 image URLs to their Supabase equivalents"

  @moduledoc """
  One-off data migration (Phase 4b of the S3 → Supabase move). For every column
  that stores an absolute image URL, rewrites any URL pointing at the legacy AWS
  bucket to the Supabase public URL for the **same key**:

      https://<bucket>.s3[.region].amazonaws.com/recipe_images/x.jpg
        → <SUPABASE_URL>/storage/v1/object/public/<bucket>/recipe_images/x.jpg

  Only AWS-owned URLs are touched; remote/third-party images and URLs already on
  Supabase are left untouched (idempotent — safe to re-run). Run the byte copy
  (`mix storage.copy_to_supabase` or rclone) **first** so the objects exist.

      mix storage.rewrite_urls              # DRY RUN — prints what would change
      mix storage.rewrite_urls --commit     # applies the UPDATEs

  A reversible mapping (table,column,id,old,new) is always written to
  `--out` (default `storage_url_rewrite.csv`) so a rollback is a trivial
  reverse-UPDATE from the CSV.
  """

  use Mix.Task

  alias Mehungry.Repo

  # {table, [url columns]} — every column holding an absolute S3/media URL.
  @targets [
    {"recipes", ["image_url", "list_image_url", "detail_image_url"]},
    {"professional_profiles", ["photo_url"]},
    {"articles", ["cover_image_url"]},
    {"article_paragraphs", ["image_url"]},
    {"posts", ["bg_media_url", "md_media_url", "sm_media_url"]}
  ]

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [commit: :boolean, out: :string])

    commit? = Keyword.get(opts, :commit, false)
    out = Keyword.get(opts, :out, "storage_url_rewrite.csv")

    Mix.Task.run("app.start")

    unless Keyword.get(Mehungry.Storage.config(), :supabase_url) do
      Mix.raise("SUPABASE_URL not configured — set it before rewriting URLs.")
    end

    rows =
      Enum.flat_map(@targets, fn {table, cols} ->
        Enum.flat_map(cols, &collect(table, &1))
      end)

    File.write!(out, encode_csv(rows))

    mode = if commit?, do: "COMMIT", else: "DRY RUN"
    Mix.shell().info("[#{mode}] #{length(rows)} URL(s) to rewrite. Mapping → #{out}")

    Enum.take(rows, 5)
    |> Enum.each(fn {t, c, id, old, new} ->
      Mix.shell().info("  #{t}.#{c} ##{id}\n    #{old}\n    → #{new}")
    end)

    if commit? do
      Enum.each(rows, fn {table, col, id, _old, new} ->
        Repo.query!(
          "UPDATE #{table} SET #{col} = $1 WHERE id = $2",
          [new, id]
        )
      end)

      Mix.shell().info("Applied #{length(rows)} update(s).")
    else
      Mix.shell().info("Dry run only — re-run with --commit to apply.")
    end
  end

  # Selects rows whose column holds an AWS-owned URL and computes the Supabase target.
  defp collect(table, col) do
    %{rows: rows} =
      Repo.query!(
        "SELECT id, #{col} FROM #{table} WHERE #{col} LIKE '%.amazonaws.com/%'",
        []
      )

    Enum.flat_map(rows, fn [id, old] ->
      key = Mehungry.Storage.key_from_url(old)
      new = Mehungry.Storage.Supabase.public_url(key)
      if new == old, do: [], else: [{table, col, id, old, new}]
    end)
  end

  defp encode_csv(rows) do
    header = "table,column,id,old_url,new_url\n"

    body =
      Enum.map_join(rows, "\n", fn {t, c, id, old, new} ->
        Enum.map_join([t, c, id, old, new], ",", &csv_field/1)
      end)

    header <> body <> "\n"
  end

  defp csv_field(v) do
    s = to_string(v)

    if String.contains?(s, [",", "\"", "\n"]),
      do: ~s("#{String.replace(s, "\"", "\"\"")}"),
      else: s
  end
end
