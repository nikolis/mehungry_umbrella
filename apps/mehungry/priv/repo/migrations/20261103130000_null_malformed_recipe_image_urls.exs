defmodule Mehungry.Repo.Migrations.NullMalformedRecipeImageUrls do
  use Ecto.Migration

  @moduledoc """
  `recipes.image_url` is meant to hold the full public URL of the cover image
  (the upload flow stores `%{public_url: url}` directly). A half-failed upload
  could instead persist a raw object key / tmp path (e.g.
  "recipe_images/tmp/<uuid>.jpg"), which has no scheme or host — so the page's
  `<img>`, `og:image`, and Recipe JSON-LD all emitted it verbatim, resolving it
  against the page path and 404-ing (broken hero image + dead social preview).

  Null every non-absolute value. These rows already rendered broken, so nulling
  is strictly an improvement: the template falls back to the default OG card and
  a placeholder hero. (A follow-up could reconstruct recoverable object keys via
  `Mehungry.Storage.public_url/1`, but tmp paths point at ephemeral objects that
  no longer exist, so there's nothing reliable to recover here.)
  """

  def up do
    execute("""
    UPDATE recipes
    SET image_url = NULL
    WHERE image_url IS NOT NULL
      AND image_url NOT LIKE 'http%'
    """)
  end

  def down do
    # Irreversible: the malformed values were broken and are intentionally
    # discarded. No-op so the migration can be rolled back without error.
    :ok
  end
end
