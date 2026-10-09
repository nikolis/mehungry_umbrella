defmodule Mix.Tasks.Storage.CopyToSupabase do
  @shortdoc "Copy image objects from the legacy S3 bucket into Supabase Storage"

  @moduledoc """
  One-off byte copy (Phase 4a of the S3 → Supabase move). Streams every object
  under the media prefixes from the legacy AWS bucket (source: `Mehungry.S3`)
  into the Supabase bucket under the **same key** (dest: `Mehungry.Storage.Supabase`),
  so URLs rewritten by `mix storage.rewrite_urls` resolve 1:1.

  Uploads use `x-upsert`, so re-running is safe/idempotent (and resumes after a
  failure). For very large buckets, `rclone` between an S3 remote and the
  Supabase S3-compatible remote is faster — this task is the dependency-free
  fallback and the source of truth for which prefixes count as "media".

      mix storage.copy_to_supabase                     # all media prefixes
      mix storage.copy_to_supabase --prefix recipe_images
      mix storage.copy_to_supabase --dry-run

  Requires both the AWS env (source bucket) and the Supabase env (destination).
  """

  use Mix.Task

  @prefixes ~w(recipe_images profile_photos article_images avatars)

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [prefix: :keep, dry_run: :boolean])

    Mix.Task.run("app.start")

    dry? = Keyword.get(opts, :dry_run, false)
    bucket = Application.fetch_env!(:mehungry_web, :aws_bucket)

    prefixes =
      case Keyword.get_values(opts, :prefix) do
        [] -> @prefixes
        ps -> ps
      end

    Enum.each(prefixes, fn prefix ->
      Mix.shell().info("== #{prefix}/ ==")
      copy_prefix(bucket, prefix, dry?)
    end)
  end

  defp copy_prefix(bucket, prefix, dry?) do
    case Mehungry.S3.list_objects(bucket, prefix <> "/") do
      {:ok, %{body: %{contents: contents}}} ->
        {ok, fail} =
          Enum.reduce(contents, {0, 0}, fn %{key: key}, {ok, fail} ->
            copy_one(bucket, key, dry?, {ok, fail})
          end)

        Mix.shell().info("  #{length(contents)} object(s): #{ok} copied, #{fail} failed")

      {:error, reason} ->
        Mix.shell().error("  list failed: #{inspect(reason)}")
    end
  end

  defp copy_one(_bucket, key, true, {ok, fail}) do
    Mix.shell().info("  would copy #{key}")
    {ok + 1, fail}
  end

  defp copy_one(bucket, key, false, {ok, fail}) do
    with {:ok, %{body: body}} <- Mehungry.S3.download_file(bucket, key),
         {:ok, _} <- Mehungry.Storage.Supabase.put(key, body, content_type: content_type(key)) do
      {ok + 1, fail}
    else
      error ->
        Mix.shell().error("  FAILED #{key}: #{inspect(error)}")
        {ok, fail + 1}
    end
  end

  defp content_type(key) do
    case key |> Path.extname() |> String.downcase() do
      "." <> _ = ext -> MIME.type(String.trim_leading(ext, "."))
      _ -> "application/octet-stream"
    end
  end
end
