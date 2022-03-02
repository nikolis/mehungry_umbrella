defmodule MehungryApi.Schemas do
  alias OpenApiSpex.Schema

  defmodule NoContent do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "NoContent",
      description: "A general response schema for Delete http operation",
      type: :object
    })
  end

  defmodule CreatedResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "CreatedResponse",
      description: "A general response schema for create/post http operation",
      type: :object,
      required: [:data],
      properties: %{
        data: %Schema{
          type: :object,
          required: [:id],
          properties: %{
            id: %Schema{type: :integer, description: "The id of the resoursce Created"}
          }
        }
      }
    })
  end

  defmodule RecipeStep do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RecipeStep",
      description:
        "The struct that holds information needed to describe the instruction to prepare a recipe in steps",
      type: :object,
      properties: %{
        index: %Schema{type: :integer, description: "The index of a particular step i.e 1, 2 ,3 "},
        title: %Schema{type: :string, description: "The title of the step", format: :string},
        description: %Schema{
          type: :string,
          description: "The detailed description of the step",
          format: :string
        }
      },
      required: [:index, :title, :description],
      example: %{
        index: 1,
        title: "Preparing the onnions",
        description:
          "Cutting the onnions vertically and then doing all kinds of interesting things"
      }
    })
  end

  defmodule RecipeIngredient do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "RecipeIngredient",
      description:
        "The struct that holds information needed to identify the ingredient entries with a recipe",
      type: :object,
      properties: %{
        quantity: %Schema{
          type: :number,
          description: "The quantity of the ingredient needed for a recipe"
        },
        measurement_unit_id: %Schema{
          type: :integer,
          description: "Language code",
          format: :string
        },
        ingredient_id: %Schema{type: :integer, description: "Language code", format: :string},
        ingredient_alias: %Schema{
          type: :string,
          description: "The alias of the ingredient"
        }
      },
      required: [:quantity, :measurement_unit_id, :ingredient_id],
      example: %{
        quantity: 22.5,
        measurement_unit_id: 44,
        ingredient_id: 14,
        ingredient_alias: "Chicken breast"
      }
    })
  end

  defmodule Recipe do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Recipe",
      description: "The struct representing all information needed to create a recipe",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "The author of the recipe"},
        author: %Schema{type: :string, description: "The author of the recipe", format: :string},
        cousine: %Schema{
          type: :string,
          description: "The cousine i.e Greek, Fitness, Chinese",
          format: :string
        },
        description: %Schema{type: :string, description: "A sort description of the recipe"},
        servings: %Schema{
          type: :integer,
          description: "The servings that all the ingredients are intented for",
          format: :string
        },
        language_name: %Schema{type: :string, description: "The language abbriviation i.e En, Gr"},
        title: %Schema{type: :string, description: "The title of the Recipe", format: :string},
        recipe_ingredients: %Schema{
          type: :array,
          items: RecipeIngredient
        },
        steps: %Schema{
          type: :array,
          items: RecipeStep
        },
        title: %Schema{type: :string, description: "The title of the step", format: :string},
        description: %Schema{
          type: :string,
          description: "The detailed description of the step",
          format: :string
        }
      },
      required: [:title, :description, :author, :id],
      example: %{
        "author" => "Nikolaos Galerakis",
        "cousine" => "Without boarders",
        "description" => "a recipe I just invented",
        "servings" => 4,
        "user" => "user name",
        "language_name" => "En",
        "title" => "tst1 gluten-free"
      }
    })
  end

  defmodule RecipeDetailed do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RecipeDetailed",
      description: "The struct representing all information needed to create a recipe",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "The author of the recipe"},
        author: %Schema{type: :string, description: "The author of the recipe", format: :string},
        cousine: %Schema{
          type: :string,
          description: "The cousine i.e Greek, Fitness, Chinese",
          format: :string
        },
        description: %Schema{type: :string, description: "A sort description of the recipe"},
        servings: %Schema{
          type: :integer,
          description: "The servings that all the ingredients are intented for",
          format: :string
        },
        language_name: %Schema{type: :string, description: "The language abbriviation i.e En, Gr"},
        title: %Schema{type: :string, description: "The title of the Recipe", format: :string},
        recipe_ingredients: %Schema{
          type: :array,
          items: RecipeIngredient
        },
        steps: %Schema{
          type: :array,
          items: RecipeStep
        },
        title: %Schema{type: :string, description: "The title of the step", format: :string},
        description: %Schema{
          type: :string,
          description: "The detailed description of the step",
          format: :string
        }
      },
      required: [:title, :description, :author, :id, :steps, :recipe_ingredients],
      example: %{
        "author" => "Nikolaos Galerakis",
        "cousine" => "Without boarders",
        "description" => "a recipe I just invented",
        "servings" => 4,
        "user" => "user name",
        "language_name" => "En",
        "title" => "tst1 gluten-free",
        "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free"}],
        "recipe_ingredients" => [
          %{
            "quantity" => 20,
            "measurement_unit_id" => 22,
            "ingredient_id" => 15,
            "ingredient_allias" => "Pork"
          },
          %{
            "quantity" => 30,
            "measurement_unit_id" => 25,
            "ingredient_id" => 15,
            "ingredient_alias" => "Basilisk Pesto"
          }
        ]
      }
    })
  end

  defmodule RecipeSearchResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "RecipeSearchResponse",
      description: "The search response",
      type: :object,
      required: [:data],
      properties: %{
        data: %Schema{
          type: :array,
          items: Recipe
        }
      }
    })
  end

  defmodule IngredientSearchParams do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "IngredientSearchParams",
      description: "The necesary params to search for an ingredient",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Search term part of the name", format: :string},
        language: %Schema{type: :string, description: "Language code", format: :string}
      },
      required: [:name, :language],
      example: %{
        name: "Chick",
        language: "En"
      }
    })
  end

  defmodule MeasurementUnitSchema do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "MeasurementUnitSchema",
      description: "Struct holding data representation of a measurement unit",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "the common name for the measurement unit i.e grammar",
          format: :string
        },
        url: %Schema{
          nullable: true,
          type: :string,
          description: "Optional a url pointing at some online resource",
          format: :string
        },
        id: %Schema{
          type: :integer,
          description: "The unique identifier identified this measurement unit"
        }
      },
      required: [:name, :id],
      example: %{
        name: "grammar",
        id: 144,
        url: "htt://www.wikipedia.com/grammar"
      }
    })
  end

  defmodule CategorySchema do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "CategorySchema",
      description: "Struct holding data representation of an ingredient category",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "the common name for the measurement unit i.e grammar",
          format: :string
        },
        description: %Schema{
          type: :string,
          nullable: true,
          description: "Optional a descirption for the category",
          format: :string
        },
        id: %Schema{
          type: :integer,
          description: "The unique identifier identifying this measurement unit"
        }
      },
      required: [:name, :id],
      example: %{
        name: "Traditional Greek",
        id: 144,
        url: "Food Recipes that are traditional to the Greek culture!"
      }
    })
  end

  defmodule IgredientSearchResponseEntry do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IngredientSearchResponseEntry",
      description: "The necesary params to search for an ingredient",
      type: :object,
      required: [:id, :name, :category, :measurement_unit],
      properties: %{
        id: %Schema{
          type: :integer,
          description: "The unique identifier identifying this measurement unit"
        },
        name: %Schema{type: :string, description: "Ingredient name", format: :string},
        description: %Schema{
          nullable: true,
          type: :string,
          description: "Optional a descirption for the ingredient",
          format: :string
        },
        url: %Schema{
          type: :string,
          nullable: true,
          description: "Optional a url pointing at some online resource",
          format: :string
        },
        category: CategorySchema,
        measurement_unit: MeasurementUnitSchema
      }
    })
  end

  defmodule IngredientSearchResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "IngredientSearchResponse",
      description: "The necesary params to search for an ingredient",
      type: :object,
      required: [:data],
      properties: %{
        data: %Schema{
          type: :array,
          items: IgredientSearchResponseEntry
        }
      }
    })
  end

  defmodule RegisterUserParams do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      # So the derived title for MyApp.User is "User".
      title: "RegisterUserParams",
      description: "The necesary params to register with the app",
      type: :object,
      properties: %{
        email: %Schema{type: :string, description: "Email address", format: :email},
        password: %Schema{type: :string, description: "Pass", format: :password},
        password_repeat: %Schema{type: :string, description: "Pass repeat", format: :password},
        inserted_at: %Schema{
          type: :string,
          description: "Creation timestamp",
          format: :"date-time"
        },
        updated_at: %Schema{type: :string, description: "Update timestamp", format: :"date-time"}
      },
      required: [:email, :password, :password_repeat],
      example: %{
        user: %{
          email: "jo23e@gmail.com",
          password: "some_password",
          password_repeat: "some_password"
        }
      }
    })
  end

  defmodule UserMealResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "UserMealResponse",
      description: "User Meal Create Params",
      type: :object,
      required: [:meal_datetime, :recipes],
      properties: %{
           meal_datetime: %Schema{
              type: :string,
              format: :datetime,
              description: "The datetime of the meal"
            },
            title: %Schema{
              type: :string,
              format: :string,
              description: "An optional Title for th email i.e breakfast"
            },
            recipes: %Schema{
              type: :array,
              items: Recipe
        }
      }
    })
  end

  defmodule UserMealListResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "UserMealListResponse",
      description: "User Meal List Response",
      type: :object,
      required: [:data],
      properties: %{
        data: %Schema{
          type: :array,
          items: UserMealResponse
        }
      }
    })
  end

  defmodule RecipeUserMealParams do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "RecipeUserMealsParams",
      description: "User Meal Create Params",
      type: :object,
      required: [:recipe_id],
      properties: %{
        recipe_id: %Schema{type: :integer, description: "The ID of the infered recipe"}
      }
    })
  end

  defmodule UserMealCreateParams do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      # The title is optional. It defaults to the last section of the module name.
      title: "UserMealCreateParams",
      description: "User Meal Create Params",
      type: :object,
      required: [:user_meal],
      properties: %{
        user_meal: %Schema{
          type: :object,
          required: [:id],
          properties: %{
            meal_datetime: %Schema{
              type: :string,
              format: :date,
              description: "The datetime of the meal"
            },
            title: %Schema{
              type: :string,
              format: :string,
              description: "An optional Title for th email i.e breakfast"
            },
            recipe_user_meals: %Schema{
              type: :array,
              items: RecipeUserMealParams
            }
          }
        }
      }
    })
  end

  defmodule LoginWithCredentialsParams do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LoginWithCredentialsParams",
      description: "Login With Credentials Parameters Schema",
      type: :object,
      properties: %{
        credential: %Schema{
          type: :object,
          required: [:email, :password],
          properties: %{
            email: %Schema{type: :string, description: "Email address", format: :email},
            password: %Schema{type: :string, description: "The password", format: :password}
          }
        }
      },
      required: [:credential],
      example: %{
        credential: %{
          email: "jo23e@gmail.com",
          password: "some_password"
        }
      }
    })
  end

  defmodule LoginResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LoginResponse",
      description: "Login With Credentials Response Schema",
      type: :object,
      properties: %{
        jwt: %Schema{
          type: :string,
          description: "The jwt token to use in order to get access to the rest endpoints",
          format: :string
        }
      },
      required: [:jwt],
      example: %{
        jwt:
          "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJtZWh1bmdyeV9hcGkiLCJleHAiOjE2NDY5MjQxNzIsImlhdCI6MTY0NDUwNDk3MiwiaXNzIjoibWVodW5ncnlfYXBpIiwianRpIjoiOWFjNzhlZWMtYTg1NS00MmJiLWE5NDMtYjc0NDhjOGQzMTBmIiwibmJmIjoxNjQ0NTA0OTcxLCJzdWIiOiI3OSIsInR5cCI6ImFjY2VzcyJ9.OmzSaVlz_WrfWCdCE_uIwweBpApuWqcUpvaYTtsHHsaOVHOHFAIB07tiLtxWwvffXcwDaSX9hgTb3tAToIJYcw"
      }
    })
  end

  defmodule RegisterUserResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RegisterUserResponse",
      description: "Response schema for registration",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          required: [:email],
          properties: %{
            email: %Schema{type: :string, description: "Email address", format: :email}
          }
        }
      },
      required: [:data],
      example: %{
        "data" => %{
          "email" => "joe23@gmail.com"
        }
      }
    })
  end
end
