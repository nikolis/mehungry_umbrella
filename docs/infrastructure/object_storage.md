# Object storage (`Mehungry.Storage`)

All image/media storage goes through the **`Mehungry.Storage`** facade — never
raw `ExAws.S3` or inline HTTP. The active backend is a single config flip, which
is what made the AWS S3 → Supabase Storage migration a runtime cutover rather
than a code change.

## Backends

`config :mehungry, :storage, backend:` selects the implementation:

| backend | module | reads/writes | browser upload |
|---|---|---|---|
| `:s3` (legacy) | `Mehungry.Storage.S3` | AWS bucket via `Mehungry.S3`/ExAws | sigv4 POST policy (`MehungryWeb.SimpleS3Upload`) |
| `:supabase` | `Mehungry.Storage.Supabase` | Supabase Storage REST (`service_role`) | signed PUT URL |

Both implement `Mehungry.Storage.Behaviour`. Tests/rollback can hard-pin a
module via `config :mehungry, :storage_impl, MyStub` (same seam style as
`:instagram_client`).

Keys are **bucket-relative paths** (e.g. `recipe_images/<uuid>.jpg`); the bucket
lives in config. The key layout (`recipe_images/`, `profile_photos/`,
`article_images/`, `avatars/`) is identical across backends so a copied object
keeps its key and its URL maps 1:1.

> The USDA **seed-file** import tooling (`S3BrowserLive`, `SeedFileImportWorker`,
> `FoodData.Usda.SeedFiles`) is a *separate* S3 concern — it browses the USDA
> data bucket and is intentionally **not** part of this facade or the migration.

## Config / env

```
STORAGE_BACKEND=supabase            # s3 (default) | supabase
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...       # server-only secret, never sent to clients
SUPABASE_STORAGE_BUCKET=media       # public bucket
```

Legacy AWS vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_ASSETS_BUCKET_NAME`) stay set through the migration grace period so old URLs
still resolve and rollback is a flag flip.

## Browser direct uploads

LiveView `allow_upload(..., external: &presign/2)` callbacks call
`MehungryWeb.Uploads.meta/3`, which returns backend-appropriate metadata always
carrying `:public_url`. Consume callbacks are therefore backend-agnostic:

```elixir
consume_uploaded_entries(socket, :image, fn %{public_url: url}, _ -> {:ok, url} end)
```

JS uploaders live in `assets/js/uploaders.js` (`Uploaders.S3`, `Uploaders.Supabase`).

## Migration (one-off, Phase 4)

1. **Copy bytes** S3 → Supabase, same keys: `mix storage.copy_to_supabase`
   (idempotent `x-upsert`; `--dry-run` first). rclone is the faster alternative
   for large buckets.
2. **Rewrite DB URLs**: `mix storage.rewrite_urls` (dry run) → `--commit`.
   Rewrites only AWS-owned URLs to the Supabase public URL for the same key,
   across `recipes`, `professional_profiles`, `articles`, `article_paragraphs`,
   `posts`. Idempotent; writes a reversible `table,column,id,old,new` CSV.

### Cutover order
Deploy (backend still `:s3`) → copy bytes → rewrite URLs (dry-run, review,
commit) → flip `STORAGE_BACKEND=supabase` → keep S3 readable for a grace period →
decommission S3 once no `amazonaws.com` URLs remain.
