defmodule Mehungry.FoodData.Wikidata.ClientTest do
  use ExUnit.Case, async: false

  alias Mehungry.FoodData.Wikidata.Client

  # Stub the HTTP seam with canned Wikidata API responses keyed on the request URL.
  setup do
    adapter = fn url, _headers, _opts ->
      body =
        cond do
          String.contains?(url, "wbsearchentities") -> search_json()
          String.contains?(url, "Special:EntityData/Q89.json") -> entity_json()
          String.contains?(url, "wbgetentities") and String.contains?(url, "Q668") -> label_json()
          String.contains?(url, "commons.wikimedia.org") -> commons_json()
          true -> ~s({})
        end

      {:ok, %{status_code: 200, body: body}}
    end

    Application.put_env(:mehungry, :wikidata_http_adapter, adapter)
    on_exit(fn -> Application.delete_env(:mehungry, :wikidata_http_adapter) end)
    :ok
  end

  test "parses qid, origin, descriptions and wikipedia links from the entity" do
    assert {:ok, result} = Client.fetch("Apple", "Malus domestica")

    assert result.qid == "Q89"
    assert result.origin_region == "India"
    assert result.descriptions == %{"en" => "species of fruit", "el" => "είδος φρούτου"}
    assert result.wikipedia_urls["en"] == "https://en.wikipedia.org/wiki/Apple"
    # elwiki carried only a title → URL built from it
    assert result.wikipedia_urls["el"] =~ "el.wikipedia.org/wiki/"
  end

  test "resolves the P18 image to a re-hostable URL + licence/attribution from Commons" do
    assert {:ok, %{image: image}} = Client.fetch("Apple", "Malus domestica")

    assert image.filename == "Apple.jpg"
    assert image.url =~ "800px-Apple.jpg"
    assert image.original_url == "https://upload.wikimedia.org/Apple.jpg"
    assert image.descriptionurl == "https://commons.wikimedia.org/wiki/File:Apple.jpg"
    assert image.license_code == "cc-by-sa-3.0"
    assert image.license_name == "CC BY-SA 3.0"
    assert image.license_url == "https://creativecommons.org/licenses/by-sa/3.0"
    # Artist HTML stripped to plain text
    assert image.artist == "Jane Doe"
  end

  test "omits :image when the entity has no P18 claim" do
    Application.put_env(:mehungry, :wikidata_http_adapter, fn url, _h, _o ->
      body =
        cond do
          String.contains?(url, "wbsearchentities") -> ~s({"search": [{"id": "Q89"}]})
          String.contains?(url, "Special:EntityData/Q89.json") -> ~s({"entities": {"Q89": {}}})
          true -> ~s({})
        end

      {:ok, %{status_code: 200, body: body}}
    end)

    assert {:ok, result} = Client.fetch("Apple", nil)
    refute Map.has_key?(result, :image)
  end

  test "returns {:ok, %{}} when the search resolves nothing" do
    Application.put_env(:mehungry, :wikidata_http_adapter, fn _u, _h, _o ->
      {:ok, %{status_code: 200, body: ~s({"search": []})}}
    end)

    assert {:ok, %{}} == Client.fetch("Nonexistent", nil)
  end

  test "swallows HTTP errors into {:ok, %{}}" do
    Application.put_env(:mehungry, :wikidata_http_adapter, fn _u, _h, _o ->
      {:error, :timeout}
    end)

    assert {:ok, %{}} == Client.fetch("Apple", "Malus domestica")
  end

  defp search_json, do: ~s({"search": [{"id": "Q89"}]})

  defp entity_json do
    ~s({
      "entities": {
        "Q89": {
          "descriptions": {
            "en": {"value": "species of fruit"},
            "el": {"value": "είδος φρούτου"}
          },
          "sitelinks": {
            "enwiki": {"title": "Apple", "url": "https://en.wikipedia.org/wiki/Apple"},
            "elwiki": {"title": "Μήλο"}
          },
          "claims": {
            "P495": [{"mainsnak": {"datavalue": {"value": {"id": "Q668"}}}}],
            "P18": [{"mainsnak": {"datavalue": {"value": "Apple.jpg"}}}]
          }
        }
      }
    })
  end

  defp label_json, do: ~s({"entities": {"Q668": {"labels": {"en": {"value": "India"}}}}})

  defp commons_json do
    ~s({
      "query": {
        "pages": {
          "-1": {
            "title": "File:Apple.jpg",
            "imageinfo": [{
              "url": "https://upload.wikimedia.org/Apple.jpg",
              "thumburl": "https://upload.wikimedia.org/thumb/Apple.jpg/800px-Apple.jpg",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:Apple.jpg",
              "extmetadata": {
                "License": {"value": "cc-by-sa-3.0"},
                "LicenseShortName": {"value": "CC BY-SA 3.0"},
                "LicenseUrl": {"value": "https://creativecommons.org/licenses/by-sa/3.0"},
                "Artist": {"value": "<a href=\\"//commons.wikimedia.org/wiki/User:Jane\\">Jane Doe</a>"}
              }
            }]
          }
        }
      }
    })
  end
end
