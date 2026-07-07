defmodule MehungryWeb.SitemapController do
  use MehungryWeb, :controller

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Recipe
  alias Mehungry.Hashtag
  alias Mehungry.Food.RecipeHashtag
  alias Mehungry.Food.Ingredient

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

    ingredients =
      Repo.all(
        from(i in Ingredient,
          where: not is_nil(i.search_name) and i.search_name != "",
          distinct: i.search_name,
          select: %{search_name: i.search_name, updated_at: i.updated_at},
          order_by: [asc: i.search_name, desc: i.updated_at]
        )
      )

    xml = build_xml(recipes, hashtags, ingredients)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  defp url_entry(loc, opts) do
    lastmod = if v = opts[:lastmod], do: "\n    <lastmod>#{v}</lastmod>", else: ""
    changefreq = opts[:changefreq] || "weekly"
    priority = opts[:priority] || "0.8"

    "<url>" <>
      "\n  <loc>#{loc}</loc>" <>
      lastmod <>
      "\n  <changefreq>#{changefreq}</changefreq>" <>
      "\n  <priority>#{priority}</priority>" <>
      "\n</url>"
  end

  defp build_xml(recipes, hashtags, ingredients) do
    today = Date.utc_today() |> to_string()

    static_urls = [
      url_entry("#{@base_url}/", changefreq: "daily", priority: "1.0"),
      url_entry("#{@base_url}/browse", changefreq: "hourly", priority: "0.9"),
      url_entry("#{@base_url}/home", changefreq: "daily", priority: "0.8")
    ]

    recipe_urls =
      Enum.map(recipes, fn r ->
        date = r.updated_at |> NaiveDateTime.to_date() |> to_string()

        url_entry("#{@base_url}/browse/#{r.id}",
          lastmod: date,
          changefreq: "weekly",
          priority: "0.8"
        )
      end)

    hashtag_urls =
      Enum.map(hashtags, fn h ->
        encoded = URI.encode(h, &URI.char_unreserved?/1)

        url_entry("#{@base_url}/search/hashtag/#{encoded}",
          lastmod: today,
          changefreq: "daily",
          priority: "0.7"
        )
      end)

    food_urls =
      Enum.map(ingredients, fn i ->
        slug = String.replace(i.search_name, " ", "-")
        date = i.updated_at |> NaiveDateTime.to_date() |> to_string()

        url_entry("#{@base_url}/foods/#{slug}",
          lastmod: date,
          changefreq: "monthly",
          priority: "0.5"
        )
      end)

    all_urls = Enum.join(static_urls ++ recipe_urls ++ hashtag_urls ++ food_urls, "\n")

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" <>
      all_urls <>
      "\n</urlset>"
  end
end
