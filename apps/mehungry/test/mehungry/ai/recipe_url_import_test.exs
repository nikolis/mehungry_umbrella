defmodule Mehungry.AI.RecipeUrlImportTest do
  use ExUnit.Case, async: false

  alias Mehungry.AI.RecipeUrlImport

  # Stub the HTTP fetch seam with a canned response for the duration of a test.
  defp stub_http(result) do
    Application.put_env(:mehungry, :recipe_url_http_adapter, fn _url, _headers, _opts ->
      result
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :recipe_url_http_adapter) end)
  end

  defp ok_html(body), do: {:ok, %HTTPoison.Response{status_code: 200, body: body}}

  describe "fetch_and_extract/1 — schema.org JSON-LD" do
    test "extracts the exact ingredient list and instructions from a Recipe node" do
      html = """
      <html><head>
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": "Spaghetti Aglio e Olio",
        "description": "A simple Roman pasta.",
        "recipeIngredient": ["400g spaghetti", "6 cloves garlic", "120ml olive oil"],
        "recipeInstructions": [
          {"@type": "HowToStep", "text": "Boil the pasta."},
          {"@type": "HowToStep", "text": "Fry the garlic in oil."},
          {"@type": "HowToStep", "text": "Toss together and serve."}
        ]
      }
      </script>
      </head><body>ignored</body></html>
      """

      stub_http(ok_html(html))

      assert {:ok, source} = RecipeUrlImport.fetch_and_extract("https://example.com/r")
      assert source.mode == :structured
      assert source.title == "Spaghetti Aglio e Olio"
      assert source.description == "A simple Roman pasta."
      assert source.ingredients == ["400g spaghetti", "6 cloves garlic", "120ml olive oil"]
      assert source.instructions == ["Boil the pasta.", "Fry the garlic in oil.", "Toss together and serve."]
      assert source.source_url == "https://example.com/r"
    end

    test "finds the Recipe node inside an @graph array and flattens HowToSection steps" do
      html = """
      <script type="application/ld+json">
      {"@context":"https://schema.org","@graph":[
        {"@type":"WebPage","name":"Blog"},
        {"@type":["Recipe","Thing"],
         "name":"Lemon Cake",
         "recipeIngredient":["2 eggs","1 lemon"],
         "recipeInstructions":[
           {"@type":"HowToSection","itemListElement":[
             {"@type":"HowToStep","text":"Beat the eggs."},
             {"@type":"HowToStep","text":"Zest the lemon."}
           ]}
         ]}
      ]}
      </script>
      """

      stub_http(ok_html(html))

      assert {:ok, source} = RecipeUrlImport.fetch_and_extract("https://example.com/cake")
      assert source.mode == :structured
      assert source.title == "Lemon Cake"
      assert source.ingredients == ["2 eggs", "1 lemon"]
      assert source.instructions == ["Beat the eggs.", "Zest the lemon."]
    end

    test "accepts plain-string recipeInstructions" do
      html = """
      <script type="application/ld+json">
      {"@type":"Recipe","name":"Toast","recipeIngredient":["bread"],
       "recipeInstructions":"Toast the bread until golden."}
      </script>
      """

      stub_http(ok_html(html))

      assert {:ok, source} = RecipeUrlImport.fetch_and_extract("https://example.com/toast")
      assert source.instructions == ["Toast the bread until golden."]
    end
  end

  describe "fetch_and_extract/1 — raw fallback" do
    test "falls back to stripped page text when there is no JSON-LD Recipe" do
      html = """
      <html><head>
      <script type="application/ld+json">{"@type":"WebSite","name":"Food Blog"}</script>
      <style>.x{color:red}</style>
      </head><body>
      <script>var tracker = 1;</script>
      <h1>Grandma's Stew</h1>
      <p>Chop &amp; simmer everything.</p>
      </body></html>
      """

      stub_http(ok_html(html))

      assert {:ok, source} = RecipeUrlImport.fetch_and_extract("https://example.com/stew")
      assert source.mode == :raw
      assert source.source_url == "https://example.com/stew"
      assert source.raw_text =~ "Grandma's Stew"
      assert source.raw_text =~ "Chop & simmer everything."
      # Script/style contents are dropped.
      refute source.raw_text =~ "tracker"
      refute source.raw_text =~ "color:red"
    end
  end

  describe "fetch_and_extract/1 — errors" do
    test "rejects a non-http(s) / malformed URL without fetching" do
      assert {:error, :invalid_url} = RecipeUrlImport.fetch_and_extract("not a url")
      assert {:error, :invalid_url} = RecipeUrlImport.fetch_and_extract("ftp://example.com/x")
      assert {:error, :invalid_url} = RecipeUrlImport.fetch_and_extract("")
    end

    test "surfaces a non-200 response as {:error, {:http, status}}" do
      stub_http({:ok, %HTTPoison.Response{status_code: 403, body: ""}})
      assert {:error, {:http, 403}} = RecipeUrlImport.fetch_and_extract("https://example.com/x")
    end

    test "surfaces a transport error" do
      stub_http({:error, %HTTPoison.Error{reason: :timeout}})
      assert {:error, :timeout} = RecipeUrlImport.fetch_and_extract("https://example.com/x")
    end
  end
end
