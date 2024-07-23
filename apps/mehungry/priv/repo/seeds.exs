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
{:ok, fr} = Mehungry.Repo.insert(%Mehungry.Food.FoodRestrictionType{title: "Absolute fun"})


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
