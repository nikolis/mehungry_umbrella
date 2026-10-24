defmodule Mehungry.FoodData.UniTools.DecoderTest do
  @moduledoc """
  Pure decoding of the UniTools dataset wrapper: English-only reduction, licence
  metadata read from the wrapper, structured ingredients → resolver-ready maps,
  steps → directions list, country → cuisine mapping, and 1-based indexing.
  """
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.UniTools.Decoder

  @dataset %{
    "name" => "UniTools World Recipes",
    "version" => "2.0.0",
    "license" => "CC BY-SA 4.0",
    "attribution" => "UniTools — theunitools.com",
    "landingPage" => "https://theunitools.com/en/data",
    "countries" => [
      %{"code" => "IT", "cuisine" => %{"ru" => "итальянская кухня", "en" => "Italian cuisine"}}
    ],
    "recipes" => [
      %{
        "slug" => "spaghetti-carbonara",
        "country" => "IT",
        "name" => %{"ru" => "Спагетти карбонара", "en" => "Spaghetti carbonara"},
        "nativeName" => "Spaghetti alla carbonara",
        "summary" => %{"ru" => "...", "en" => "Pasta from four ingredients."},
        "category" => "main",
        "difficulty" => "medium",
        "baseServings" => 2,
        "prepMinutes" => 10,
        "cookMinutes" => 15,
        "nutritionPerServing" => %{"calories" => 690},
        "ingredients" => [
          %{"name" => %{"en" => "Spaghetti"}, "quantity" => 200, "unit" => "g", "note" => nil},
          %{
            "name" => %{"en" => "Guanciale"},
            "quantity" => 100,
            "unit" => "g",
            "note" => %{"ru" => "...", "en" => "cut into strips"}
          },
          %{"name" => %{"en" => "Egg yolks"}, "quantity" => 3, "unit" => "piece", "note" => nil}
        ],
        "steps" => [
          %{"text" => %{"ru" => "...", "en" => "Boil the water."}, "minutes" => 8},
          %{"text" => %{"ru" => "...", "en" => "Crisp the guanciale."}, "minutes" => 8}
        ]
      }
    ]
  }

  test "reads licence/attribution/landing from the wrapper (not hardcoded)" do
    %{meta: meta} = Decoder.decode(@dataset)

    assert meta.license == "CC BY-SA 4.0"
    assert meta.attribution == "UniTools — theunitools.com"
    assert meta.landing_page == "https://theunitools.com/en/data"
    assert meta.name == "UniTools World Recipes"
  end

  test "reduces a recipe to English with 1-based index and mapped cuisine" do
    %{recipes: [recipe]} = Decoder.decode(@dataset)

    assert recipe.index == 1
    assert recipe.title == "Spaghetti carbonara"
    assert recipe.native_name == "Spaghetti alla carbonara"
    assert recipe.summary == "Pasta from four ingredients."
    assert recipe.cuisine == "Italian cuisine"
    assert recipe.servings == 2
    # "medium" → 2.
    assert recipe.difficulty == 2
    assert recipe.prep_minutes == 10
    assert recipe.cook_minutes == 15
  end

  test "builds resolver-ready normalized ingredient maps" do
    %{recipes: [recipe]} = Decoder.decode(@dataset)

    assert [spaghetti, guanciale, yolks] = recipe.ingredients

    assert spaghetti == %{
             name: "Spaghetti",
             quantity: 200.0,
             unit: "g",
             original: "200 g Spaghetti"
           }

    # English note folded into the display original only.
    assert guanciale.original == "100 g Guanciale (cut into strips)"
    # "piece" unit is dropped from the display line (reads awkwardly) but kept as
    # the structured unit for the resolver.
    assert yolks.unit == "piece"
    assert yolks.original == "3 Egg yolks"
  end

  test "steps become an ordered list of English direction strings" do
    %{recipes: [recipe]} = Decoder.decode(@dataset)

    assert recipe.directions == ["Boil the water.", "Crisp the guanciale."]
  end
end
