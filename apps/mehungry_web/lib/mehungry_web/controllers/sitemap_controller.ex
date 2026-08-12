defmodule MehungryWeb.SitemapController do
  use MehungryWeb, :controller

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Recipe
  alias Mehungry.Hashtag
  alias Mehungry.Food.RecipeHashtag
  alias Mehungry.Food.FoundementalFoodSpecies

  @base_url "https://www.m3hungry.com"

  def index(conn, _params) do
    recipes =
      Repo.all(
        from(r in Recipe,
          where: is_nil(r.private) or r.private == false,
          select: %{id: r.id, updated_at: r.updated_at},
          order_by: [desc: r.updated_at]
        )
      )

    hashtags =
      Repo.all(
        from(h in Hashtag,
          join: rh in RecipeHashtag,
          on: rh.hashtag_id == h.id,
          where: not is_nil(h.title) and h.title != "",
          group_by: h.title,
          having: count(rh.id) > 1,
          select: h.title,
          order_by: [desc: count(rh.id)],
          limit: 200
        )
      )

    species =
      Repo.all(
        from(s in FoundementalFoodSpecies,
          where: not is_nil(s.name) and s.name != "",
          distinct: s.name,
          select: %{name: s.name, updated_at: s.updated_at},
          order_by: [asc: s.name, desc: s.updated_at]
        )
      )

    xml = build_xml(recipes, hashtags, species)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  # Emit one <url> per supported locale for a bare (locale-less) content path,
  # each carrying reciprocal <xhtml:link rel="alternate" hreflang> entries + an
  # x-default, per the sitemap i18n spec.
  defp localized_entries(bare_path, opts) do
    locales = MehungryWeb.Locale.supported()
    default = MehungryWeb.Locale.default()

    alternates =
      Enum.map(locales, fn loc -> {loc, alt_url(bare_path, loc)} end) ++
        [{"x-default", alt_url(bare_path, default)}]

    links =
      Enum.map_join(alternates, "", fn {hreflang, href} ->
        "\n  <xhtml:link rel=\"alternate\" hreflang=\"#{hreflang}\" href=\"#{href}\" />"
      end)

    Enum.map_join(locales, "\n", fn loc -> url_entry(alt_url(bare_path, loc), links, opts) end)
  end

  defp alt_url(bare_path, locale), do: @base_url <> MehungryWeb.Locale.swap_path(bare_path, locale)

  defp url_entry(loc, alt_links, opts) do
    lastmod = if v = opts[:lastmod], do: "\n  <lastmod>#{v}</lastmod>", else: ""
    changefreq = opts[:changefreq] || "weekly"
    priority = opts[:priority] || "0.8"

    "<url>" <>
      "\n  <loc>#{loc}</loc>" <>
      lastmod <>
      alt_links <>
      "\n  <changefreq>#{changefreq}</changefreq>" <>
      "\n  <priority>#{priority}</priority>" <>
      "\n</url>"
  end

  defp build_xml(recipes, hashtags, species) do
    today = Date.utc_today() |> to_string()

    static_urls = [
      localized_entries("/home", changefreq: "daily", priority: "1.0"),
      localized_entries("/browse", changefreq: "hourly", priority: "0.9"),
      localized_entries("/foods", changefreq: "daily", priority: "0.7")
    ]

    recipe_urls =
      Enum.map(recipes, fn r ->
        date = r.updated_at |> NaiveDateTime.to_date() |> to_string()

        localized_entries("/browse/#{r.id}",
          lastmod: date,
          changefreq: "weekly",
          priority: "0.8"
        )
      end)

    hashtag_urls =
      Enum.map(hashtags, fn h ->
        encoded = URI.encode(h, &URI.char_unreserved?/1)

        localized_entries("/search/hashtag/#{encoded}",
          lastmod: today,
          changefreq: "daily",
          priority: "0.7"
        )
      end)

    food_urls =
      Enum.map(species, fn s ->
        slug = String.replace(s.name, " ", "-")
        date = s.updated_at |> NaiveDateTime.to_date() |> to_string()

        localized_entries("/foods/#{slug}",
          lastmod: date,
          changefreq: "monthly",
          priority: "0.5"
        )
      end)

    all_urls = Enum.join(static_urls ++ recipe_urls ++ hashtag_urls ++ food_urls, "\n")

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">\n" <>
      all_urls <>
      "\n</urlset>"
  end
end
