defmodule MehungryWeb.Plugs.CanonicalFoodSlug do
  @moduledoc """
  301-redirects a non-canonical `/foods/:slug` (and the localized
  `/:locale/foods/:slug`) to the clean slug `Mehungry.Food.species_slug/1` emits.

  Until 2026-11-17 the slug encoder only hyphenated spaces, so punctuated species
  names were published — and indexed by Google — as `/foods/Duck-(domesticated)`,
  `/foods/Dates,-medjool`, `/foods/Cabbage--`. The shared clean encoder changed
  their canonical to `/foods/Duck-domesticated` etc., while the decode-tolerant
  lookup kept the old URLs answering 200. A 200 + `rel=canonical` is only a hint;
  a 301 moves the old URL's ranking signals onto the new one deterministically.

  The check is a pure string comparison (no DB lookup): a slug that the clean
  encoder would rewrite is by definition not the canonical one. Unknown foods
  still 404 at the destination. Query strings are preserved; only GET/HEAD are
  redirected.
  """
  import Plug.Conn

  alias Mehungry.Food
  alias MehungryWeb.Locale

  def init(opts), do: opts

  def call(%Plug.Conn{method: method, path_info: path_info} = conn, _opts)
      when method in ["GET", "HEAD"] do
    case food_slug(path_info) do
      {locale, raw_slug} -> maybe_redirect(conn, locale, raw_slug)
      :no -> conn
    end
  end

  def call(conn, _opts), do: conn

  # /foods/:slug and /:locale/foods/:slug
  defp food_slug(["foods", slug]), do: {nil, slug}

  defp food_slug([locale, "foods", slug]) do
    if Locale.supported?(locale), do: {locale, slug}, else: :no
  end

  defp food_slug(_), do: :no

  defp maybe_redirect(conn, locale, raw_slug) do
    slug = decode(raw_slug)
    clean = Food.species_slug(slug)

    if clean != "" and clean != slug do
      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(to: target_path(locale, clean) <> query(conn))
      |> halt()
    else
      conn
    end
  end

  # `path_info` segments are still percent-encoded at this point in the pipeline.
  # A malformed escape is left as-is and falls through to the router.
  defp decode(segment) do
    URI.decode(segment)
  rescue
    ArgumentError -> segment
  end

  # Re-encode for the Location header (Greek slugs are non-ASCII).
  defp target_path(nil, slug), do: "/foods/" <> URI.encode(slug, &URI.char_unreserved?/1)

  defp target_path(locale, slug),
    do: "/#{locale}/foods/" <> URI.encode(slug, &URI.char_unreserved?/1)

  defp query(%Plug.Conn{query_string: ""}), do: ""
  defp query(%Plug.Conn{query_string: qs}), do: "?" <> qs
end
