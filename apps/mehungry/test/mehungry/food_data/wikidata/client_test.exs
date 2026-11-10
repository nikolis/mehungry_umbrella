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
            "P495": [{"mainsnak": {"datavalue": {"value": {"id": "Q668"}}}}]
          }
        }
      }
    })
  end

  defp label_json, do: ~s({"entities": {"Q668": {"labels": {"en": {"value": "India"}}}}})
end
