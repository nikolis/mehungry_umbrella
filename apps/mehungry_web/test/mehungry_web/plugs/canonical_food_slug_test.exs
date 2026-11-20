defmodule MehungryWeb.Plugs.CanonicalFoodSlugTest do
  use MehungryWeb.ConnCase, async: true

  alias MehungryWeb.Plugs.CanonicalFoodSlug

  defp run(path), do: CanonicalFoodSlug.call(build_conn(:get, path), [])

  defp location(conn), do: conn |> get_resp_header("location") |> List.first()

  test "301s an old punctuated slug to the clean slug, keeping the locale" do
    conn = run("/en/foods/Duck-(domesticated)")

    assert conn.halted
    assert conn.status == 301
    assert location(conn) == "/en/foods/Duck-domesticated"
  end

  test "handles percent-encoded punctuation, commas, and doubled/trailing hyphens" do
    assert location(run("/en/foods/Duck-%28domesticated%29")) == "/en/foods/Duck-domesticated"
    assert location(run("/en/foods/Dates,-medjool")) == "/en/foods/Dates-medjool"
    assert location(run("/en/foods/Cabbage--")) == "/en/foods/Cabbage"
    assert location(run("/foods/lobster,-northern")) == "/foods/lobster-northern"
  end

  test "preserves the query string" do
    assert location(run("/en/foods/Dates,-medjool?ref=x")) == "/en/foods/Dates-medjool?ref=x"
  end

  test "re-encodes a non-ASCII (Greek) slug in the Location header" do
    conn = run("/el/foods/" <> URI.encode("Πάπια-(οικόσιτη)"))

    assert conn.status == 301
    assert location(conn) == "/el/foods/" <> URI.encode("Πάπια-οικόσιτη")
  end

  test "passes clean slugs and unrelated paths straight through" do
    for path <- [
          "/en/foods/Cherry",
          "/foods/Brussels-sprouts",
          "/el/foods/" <> URI.encode("Κάρδαμο"),
          "/en/foods",
          "/en/browse/12",
          "/xx/foods/Dates,-medjool"
        ] do
      conn = run(path)
      refute conn.halted, "expected #{path} to pass through"
      assert conn.status == nil
    end
  end

  test "does not redirect non-GET requests" do
    conn = CanonicalFoodSlug.call(build_conn(:post, "/en/foods/Dates,-medjool"), [])
    refute conn.halted
  end

  test "is wired into the browser pipeline", %{conn: conn} do
    conn = get(conn, "/en/foods/Dates,-medjool")
    assert redirected_to(conn, 301) == "/en/foods/Dates-medjool"
  end
end
