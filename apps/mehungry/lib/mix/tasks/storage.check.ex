defmodule Mix.Tasks.Storage.Check do
  @shortdoc "Verify Supabase Storage connectivity end-to-end"

  @moduledoc """
  Smoke-tests the Supabase Storage backend before running the migration: writes
  a tiny object, reads it back, prints its public URL, and deletes it. Exercises
  `Mehungry.Storage.Supabase` directly (independent of the `STORAGE_BACKEND`
  flag), so a green run means credentials + bucket + public access all work.

      SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... mix storage.check

  Requires `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_STORAGE_BUCKET`.
  """

  use Mix.Task

  alias Mehungry.Storage.Supabase

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    cfg = Mehungry.Storage.config()

    unless cfg[:supabase_url] && cfg[:service_role_key] do
      Mix.raise("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.")
    end

    key = "storage_check/#{Ecto.UUID.generate()}.txt"
    payload = "mehungry storage check #{DateTime.utc_now()}"

    Mix.shell().info("bucket:  #{cfg[:bucket]}")
    Mix.shell().info("url:     #{cfg[:supabase_url]}")
    Mix.shell().info("key:     #{key}\n")

    step("upload (service_role PUT)", fn -> Supabase.put(key, payload, content_type: "text/plain") end)

    public = Supabase.public_url(key)
    Mix.shell().info("  public_url: #{public}")

    step("read back (authenticated GET)", fn ->
      case Supabase.get(key) do
        {:ok, ^payload} -> {:ok, :matches}
        {:ok, other} -> {:error, {:mismatch, other}}
        err -> err
      end
    end)

    step("public read (unauthenticated GET)", fn -> public_get(public) end)
    step("delete", fn -> Supabase.delete(key) end)

    Mix.shell().info("\n✅ Supabase Storage is reachable and the bucket is writable + public.")
  end

  defp step(label, fun) do
    case fun.() do
      {:ok, _} ->
        Mix.shell().info("  ✓ #{label}")

      {:error, reason} ->
        Mix.raise("✗ #{label} FAILED: #{inspect(reason)}")
    end
  end

  # Confirms the object is world-readable via the public path (no auth header) —
  # i.e. the stored public URLs will actually serve to browsers.
  defp public_get(url) do
    case HTTPoison.get(url, [], recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:ok, :public}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:not_public, status, "is bucket '#{Mehungry.Storage.config()[:bucket]}' marked public?"}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
