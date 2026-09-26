# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Mehungry.Repo.insert!(%Mehungry.SomeSchema{})
#
require Logger

{:ok, language_gr} = Mehungry.Repo.insert(%Mehungry.Languages.Language{name: "Gr"})
{:ok, language_en} = Mehungry.Repo.insert(%Mehungry.Languages.Language{name: "En"})

{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Absolutely not"})
{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Not a fun"})
{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Neutral"})
{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Fun"})
{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Absolutely fun"})

Mehungry.Food.TaxonomySeeder.seed()

Mehungry.Food.ParserVocabularySeeder.seed()

"""
{:ok, gram} = Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnit{name: "gram"})
{:ok, kg} = Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnit{name: "kg"})
{:ok, ml} = Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnit{name: "ml"})
{:ok, mg} = Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnit{name: "mg"})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "γραμμάριο",
  language_name: language_gr.name,
  measurement_unit_id: gram.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "gram",
  language_name: language_en.name,
  measurement_unit_id: gram.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "κιλό",
  language_name: language_gr.name,
  measurement_unit_id: kg.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "kg",
  language_name: language_en.name,
  measurement_unit_id: kg.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "ml",
  language_name: language_gr.name,
  measurement_unit_id: ml.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "ml",
  language_name: language_en.name,
  measurement_unit_id: ml.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "mg",
  language_name: language_gr.name,
  measurement_unit_id: mg.id
})

Mehungry.Repo.insert(%Mehungry.Food.MeasurementUnitTranslation{
  name: "mg",
  language_name: language_en.name,
  measurement_unit_id: mg.id
})

{:ok, dairy} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Dairy"})
{:ok, vegetables} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Vegetables"})
{:ok, fruits} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Fruits"})
{:ok, baking_and_grains} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Baking & Grains"})
{:ok, added_sweeteners} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Added sweeteners"})
{:ok, spices} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Spices"})
{:ok, meats} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Meats"})
{:ok, fish} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Fish"})
{:ok, seafood} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Seafood"})
{:ok, oils} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Oils"})
{:ok, seasonigs} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Seasonigs"})
{:ok, sauces} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Sauces"})
{:ok, legumes} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Legumes"})
{:ok, alcohol} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Alcohol"})
{:ok, soup} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Soup"})
{:ok, nuts} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Nuts"})

{:ok, dairy_alternatives} =
  Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Dairy Alternatives"})

{:ok, deasert_and_snacks} =
  Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Deserts & Snacks"})

{:ok, beverages} = Mehungry.Repo.insert(%Mehungry.Food.Category{name: "Beverages"})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Καρυκεύματα",
  category_id: seasonigs.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "seasonings",
  category_id: seasonigs.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Σάλτσες",
  category_id: sauces.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "sauces",
  category_id: sauces.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Όσπρια",
  category_id: legumes.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "legumes",
  category_id: legumes.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Αλκοολούχα",
  category_id: alcohol.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "alcohol",
  category_id: alcohol.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Σούπες",
  category_id: soup.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Soups",
  category_id: soup.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Ξηροι καρποί",
  category_id: nuts.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "nuts",
  category_id: nuts.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Κρέας",
  category_id: meats.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Meat",
  category_id: meats.id,
  language_name: language_en.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Yποκατάστατα γαλακτοκομικών",
  category_id: dairy_alternatives.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Snack",
  category_id: deasert_and_snacks.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Ποτά",
  category_id: beverages.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Γαλακτοκομεικά",
  category_id: dairy.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Λαχανικά",
  category_id: vegetables.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Φρούτα",
  category_id: fruits.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "ψησίματος και καρποί",
  category_id: baking_and_grains.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "πρόσθετα γλυκαντικά",
  category_id: added_sweeteners.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "μπαχαρικά",
  category_id: spices.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Ψάρι",
  category_id: fish.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Θαλασιννά",
  category_id: seafood.id,
  language_name: language_gr.name
})

Mehungry.Repo.insert(%Mehungry.Food.CategoryTranslation{
  name: "Λάδι",
  category_id: oils.id,
  language_name: language_gr.name
})

{_, chicken_breast} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "chicken breast",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "κοτόπουλο στοίθος",
  language_name: language_gr.name,
  ingredient_id: chicken_breast.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "chicken breast",
  language_name: language_en.name,
  ingredient_id: chicken_breast.id
})

{_, broccoli} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "broccoli",
    category: vegetables,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "μπροκοο",
  language_name: language_gr.name,
  ingredient_id: broccoli.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "broccoli",
  language_name: language_en.name,
  ingredient_id: broccoli.id
})

{_, lentiles} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "lentils",
    category: legumes,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "φακες",
  language_name: language_gr.name,
  ingredient_id: lentiles.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "lentils",
  language_name: language_en.name,
  ingredient_id: lentiles.id
})

# Recipe First
{:ok, user} =
  Mehungry.Accounts.register_user(%{email: "some@mailer.com", password: "some_long_pass"})

{:ok, recipe_1} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Meet Intensive 1",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: chicken_breast.id, measurement_unit_id: gram.id, quantity: 25.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.0}
    ]
  })

{:ok, recipe_2} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Meet Intensive 2",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: chicken_breast.id, measurement_unit_id: gram.id, quantity: 15.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.0}
    ]
  })

{:ok, recipe_3} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Meet Intensive 3",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: chicken_breast.id, measurement_unit_id: gram.id, quantity: 25.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.0}
    ]
  })

{:ok, recipe_4} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian 4",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 25.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.0}
    ]
  })

{:ok, recipe_5} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian 5",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 15.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.0}
    ]
  })

{:ok, recipe_6} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian  6",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 25.6},
      %{ingredient_id: broccoli.id, measurement_unit_id: gram.id, quantity: 10.9}
    ]
  })

{:ok, recipe_7} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian 7",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 25.6}
    ]
  })

{:ok, recipe_8} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian 8",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 15.6}
    ]
  })

{:ok, recipe_9} =
  Mehungry.Repo.insert(%Mehungry.Food.Recipe{
    title: "Vegeterian  9",
    language_name: language_en.name,
    user_id: user.id,
    steps: [%{title: "Step title", description: "Description"}],
    recipe_ingredients: [
      %{ingredient_id: lentiles.id, measurement_unit_id: gram.id, quantity: 25.6}
    ]
  })

# Recipe Second

# Recipe Third

{:ok, ground_beef} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "ground beef",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "κιμας μοσχαρίσιος",
  language_name: language_gr.name,
  ingredient_id: ground_beef.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "ground beef",
  language_name: language_en.name,
  ingredient_id: ground_beef.id
})

# {:ok, bacon} = Mehungry.Repo.insert(%Mehungry.Food.Ingredient{name: "bacon", category: meats, measurement_unit: gram})
# Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{name: "μπέικον", language_name: language_gr.name, ingredient_id: bacon.id})

{:ok, sausage} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "sausage",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "λουκάνικο",
  language_name: language_gr.name,
  ingredient_id: sausage.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "sausage",
  language_name: language_en.name,
  ingredient_id: sausage.id
})

{:ok, beef_steak} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "beef steak",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "μοσχαρίσια μπριζόλα",
  language_name: language_gr.name,
  ingredient_id: beef_steak.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "beef steak",
  language_name: language_en.name,
  ingredient_id: beef_steak.id
})

{:ok, ham} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "ham",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "ζαμπόν",
  language_name: language_gr.name,
  ingredient_id: ham.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "ham",
  language_name: language_en.name,
  ingredient_id: ham.id
})

{:ok, hot_dog} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "hot dog",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "λουκάνικο",
  language_name: language_gr.name,
  ingredient_id: hot_dog.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "hot dog",
  language_name: language_en.name,
  ingredient_id: hot_dog.id
})

{:ok, pork_chops} =
  Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
    name: "pork chops",
    category: meats,
    measurement_unit: gram
  })

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "χοιρινη μπριζόλα",
  language_name: language_gr.name,
  ingredient_id: hot_dog.id
})

Mehungry.Repo.insert(%Mehungry.Food.IngredientTranslation{
  name: "pork chops",
  language_name: language_en.name,
  ingredient_id: hot_dog.id
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chicken thighs",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "ground turkey",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "cooked chicken",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "turkey",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pepperoni",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "whole chicken",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chicken leg",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "ground pork",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chorizo",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chicken wings",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "beef roast",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork roast",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "ground chicken",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork ribs",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "venison",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork shoulder",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "bologna",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "bratwurst",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "prosciutto",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "lamb",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chicken roast",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "lamb chops",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pancetta",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "ground lamb",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "beef ribs",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "duck",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork belly",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "beef liver",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "leg of lamb",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "canadian bacon",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "beef shank",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "veal",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "chicken giblets",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "cornish hen",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "lamb shoulder",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "lamb shank",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "deer",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "ground veal",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pastrami",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "rabbit",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "slicked turkey",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "pork loin",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "elk",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "beef suet",
  category: meats,
  measurement_unit: gram
})

Mehungry.Repo.insert(%Mehungry.Food.Ingredient{
  name: "corned beef",
  category: meats,
  measurement_unit: gram
  })
"""

# ── Health condition registry (bulk catalogue) ───────────────────────────────
# Idempotent bulk load of the ~193-condition reference registry from
# priv/repo/seeds/data/health_conditions.json (name/synonyms/category/
# subcategory/description). Conditions only — no compound advice.
{:ok, %{inserted: inserted, total: total}} = Mehungry.Health.ConditionSeeder.seed()
IO.puts("Seeded health conditions: #{inserted} new, #{total} total.")

# ── Health conditions + compound recommendations (advice layer) ──────────────
# Idempotent: upserts the referenced compound, then find-or-creates the condition
# and links it via a guideline recommendation. Conditions link to COMPOUNDS only;
# the implicated food species resolve at read time (Health.species_for_condition/2).
# Each guideline recommendation carries a structured `source_reference` so a
# non-PubMed conclusion still cites a real, clickable source (the CompoundRecommendation
# citation invariant — see docs/science/scientific_pipeline.md).
health_seeds = [
  {"Kidney Stones", "renal", "Oxalate", "oxalate",
   %{
     recommendation: "avoid",
     severity: "high",
     evidence_level: "strong",
     source_reference: %{
       "label" => "National Kidney Foundation — Oxalate & kidney stones",
       "url" => "https://www.kidney.org/atoz/content/what-you-should-know-about-oxalate"
     }
   }},
  {"Gout", "metabolic", "Purine", "purine",
   %{
     recommendation: "limit",
     severity: "moderate",
     evidence_level: "strong",
     source_reference: %{
       "label" => "American College of Rheumatology — Gout management guideline",
       "url" => "https://rheumatology.org/patients/gout"
     }
   }},
  {"IBS", "gastrointestinal", "FODMAP", "fodmap",
   %{
     recommendation: "limit",
     severity: "moderate",
     evidence_level: "moderate",
     source_reference: %{
       "label" => "Monash University — Low FODMAP diet for IBS",
       "url" => "https://www.monashfodmap.com/"
     }
   }},
  {"Histamine Intolerance", "immune", "Histamine", "histamine",
   %{
     recommendation: "avoid",
     severity: "high",
     evidence_level: "moderate",
     source_reference: %{
       "label" => "Maintz & Novak (2007) — Histamine and histamine intolerance",
       "url" => "https://pubmed.ncbi.nlm.nih.gov/17490952/",
       "pmid" => 17_490_952
     }
   }},
  {"Salicylate Sensitivity", "immune", "Salicylate", "salicylate",
   %{
     recommendation: "avoid",
     severity: "moderate",
     evidence_level: "limited",
     source_reference: %{
       "label" => "Baenkler (2008) — Salicylate intolerance",
       "url" => "https://pubmed.ncbi.nlm.nih.gov/18631502/",
       "pmid" => 18_631_502
     }
   }}
]

for {condition_name, category, compound_name, compound_type, rec} <- health_seeds do
  {:ok, compound} =
    Mehungry.Food.upsert_compound(%{name: compound_name, compound_type: compound_type})

  {:ok, _} =
    Mehungry.Health.add_recommendation(
      %{name: condition_name, category: category},
      compound.id,
      Map.put(rec, :source, "guideline")
    )
end

IO.puts("Seeded #{length(health_seeds)} health conditions with compound recommendations.")

# ── Anti-Inflammatory: a generic dietary-pattern indication ──────────────────
# Presents like a condition everywhere a condition is selectable. Backed by BOTH
# engines: compound recommendations (encourage polyphenols/flavonoids) so it shows
# in the compound-gated pickers, and nutrient recommendations (the Mehungry.Health
# nutrient layer) which resolve to real foods via the populated USDA
# ingredient_nutrients table. Idempotent (upserts on natural keys).
{:ok, anti_inflammatory} =
  Mehungry.Health.upsert_condition(%{
    name: "Anti-Inflammatory",
    category: "dietary_pattern",
    description:
      "A generic anti-inflammatory eating pattern: favour foods rich in omega-3, " <>
        "fibre, polyphenols and monounsaturated fat; limit saturated fat, added sugar " <>
        "and sodium."
  })

# Compound side — encourage anti-inflammatory bioactive families.
anti_inflammatory_compounds = [
  {"Polyphenols", "polyphenol",
   %{
     "label" => "Harvard T.H. Chan School of Public Health — Foods that fight inflammation",
     "url" => "https://www.health.harvard.edu/staying-healthy/foods-that-fight-inflammation"
   }},
  {"Flavonoids", "polyphenol",
   %{
     "label" => "Maleki et al. (2019) — Anti-inflammatory effects of flavonoids",
     "url" => "https://pubmed.ncbi.nlm.nih.gov/30670267/",
     "pmid" => 30_670_267
   }}
]

for {compound_name, compound_type, reference} <- anti_inflammatory_compounds do
  {:ok, compound} =
    Mehungry.Food.upsert_compound(%{name: compound_name, compound_type: compound_type})

  {:ok, _} =
    Mehungry.Health.add_recommendation(anti_inflammatory.id, compound.id, %{
      recommendation: "encourage",
      severity: "moderate",
      evidence_level: "moderate",
      source: "guideline",
      source_reference: reference
    })
end

# Nutrient side — encourage/limit nutrients. `nutrient_name` must match a
# Mehungry.Health.NutrientTargets label so it resolves to foods.
anti_inflammatory_nutrients = [
  {"Omega-3", "encourage", "strong",
   %{
     "label" => "AHA — Fish and Omega-3 Fatty Acids",
     "url" =>
       "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/fats/fish-and-omega-3-fatty-acids"
   }},
  {"Fiber", "encourage", "moderate",
   %{
     "label" => "Harvard T.H. Chan — Fiber and inflammation",
     "url" => "https://nutritionsource.hsph.harvard.edu/carbohydrates/fiber/"
   }},
  {"Monounsaturated Fat", "encourage", "moderate",
   %{
     "label" => "EFSA — Scientific opinion on dietary reference values for fats",
     "url" => "https://www.efsa.europa.eu/en/efsajournal/pub/1461"
   }},
  {"Vitamin C", "encourage", "limited",
   %{
     "label" => "NIH Office of Dietary Supplements — Vitamin C",
     "url" => "https://ods.od.nih.gov/factsheets/VitaminC-HealthProfessional/"
   }},
  {"Vitamin E", "encourage", "limited",
   %{
     "label" => "NIH Office of Dietary Supplements — Vitamin E",
     "url" => "https://ods.od.nih.gov/factsheets/VitaminE-HealthProfessional/"
   }},
  {"Saturated Fat", "limit", "moderate",
   %{
     "label" => "AHA — Saturated Fat",
     "url" => "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/fats/saturated-fats"
   }},
  {"Added Sugar", "limit", "moderate",
   %{
     "label" => "AHA — Added Sugars",
     "url" => "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/sugar/added-sugars"
   }},
  {"Sodium", "limit", "limited",
   %{
     "label" => "AHA — How much sodium should I eat per day?",
     "url" =>
       "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/sodium/how-much-sodium-should-i-eat-per-day"
   }}
]

for {nutrient_name, recommendation, evidence_level, reference} <- anti_inflammatory_nutrients do
  {:ok, _} =
    Mehungry.Health.add_nutrient_recommendation(anti_inflammatory.id, nutrient_name, %{
      recommendation: recommendation,
      severity: "moderate",
      evidence_level: evidence_level,
      source: "guideline",
      source_reference: reference
    })
end

IO.puts(
  "Seeded Anti-Inflammatory indication: #{length(anti_inflammatory_compounds)} compound + " <>
    "#{length(anti_inflammatory_nutrients)} nutrient recommendations."
)

# ── AI-bot personas (authoring voices) ───────────────────────────────────────
# Idempotent: find-or-create by name. Personas are the reusable voice; a
# RecipeSetup binds one to a place/story/ingredients/condition.
persona_seeds = [
  %{
    name: "Village Grandma",
    archetype: "grandmother",
    description: "A grandmother cooking from a mountain village.",
    uses_hashtags: false,
    default_origin: "a mountain village",
    voice_prompt:
      "You are a grandmother who has cooked for her family in a mountain village for " <>
        "sixty years. You cook from what the garden and the season give you. You measure " <>
        "by feel and memory — a handful of this, a good glug of that — not by grams. You " <>
        "speak plainly and warmly, you tuck in little asides about who taught you the dish " <>
        "and when you make it, and you never reach for restaurant words or marketing gloss."
  },
  %{
    name: "Auntie",
    archetype: "aunt",
    description: "The generous aunt who feeds everyone who walks in.",
    uses_hashtags: false,
    default_origin: nil,
    voice_prompt:
      "You are the aunt everyone's glad to visit because you always have something on the " <>
        "stove. You cook generously and a little chaotically, you insist people eat more, " <>
        "and you explain things the way you'd explain them across the kitchen table — " <>
        "encouraging, forgiving of mistakes, full of shortcuts you swear by."
  },
  %{
    name: "Local Tavern",
    archetype: "tavern",
    description: "A small family taverna's daily cooking.",
    uses_hashtags: false,
    default_origin: nil,
    voice_prompt:
      "You are the cook at a small family taverna. Your food is honest, rustic and built " <>
        "for sharing at a long table with wine. You write the way the day's specials are " <>
        "read out — unfussy, confident, rooted in local produce and tradition, never " <>
        "precious or plated-for-Instagram."
  },
  %{
    name: "Restaurant Chef",
    archetype: "restaurant",
    description: "A polished restaurant kitchen voice.",
    uses_hashtags: true,
    default_origin: nil,
    voice_prompt:
      "You are a restaurant chef presenting a refined but approachable dish. You care about " <>
        "technique, precision and presentation, and you explain the why behind each step. " <>
        "Your tone is confident and modern without being pretentious."
  },
  %{
    name: "Dietologist",
    archetype: "dietologist",
    description: "A clinical nutrition professional.",
    uses_hashtags: false,
    default_origin: nil,
    voice_prompt:
      "You are a clinical dietologist designing a dish to be both genuinely enjoyable and " <>
        "suited to a specific dietary need. You are calm, precise and evidence-minded: you " <>
        "note why choices support the goal, keep portions and balance in mind, and avoid " <>
        "hype. You never make medical promises."
  }
]

for attrs <- persona_seeds do
  case Mehungry.Repo.get_by(Mehungry.AI.Bot.Persona, name: attrs.name) do
    nil -> {:ok, _} = Mehungry.AI.Bot.create_persona(attrs)
    _persona -> :ok
  end
end

IO.puts("Seeded #{length(persona_seeds)} AI-bot personas.")
