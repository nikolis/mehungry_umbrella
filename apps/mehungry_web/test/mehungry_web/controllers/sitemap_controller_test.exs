defmodule MehungryWeb.SitemapControllerTest do
  use MehungryWeb.ConnCase, async: true

  test "GET /sitemap.xml includes the curated nutrient-claim filter pages", %{conn: conn} do
    body = conn |> get("/sitemap.xml") |> response(200)

    assert body =~ "/search/nutrient/iron"
    assert body =~ "/search/nutrient/vitamin-c"
    # Localized alternate (hreflang) entries are emitted for each.
    assert body =~ "/el/search/nutrient/iron"
  end
end
