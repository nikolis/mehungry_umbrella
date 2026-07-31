defmodule Mehungry.ParserFixtures do
  @moduledoc """
  DB-free fixtures for the USDA description parser tests: a golden vocabulary
  mirroring the seed set, plus token/result builders for rule unit tests.
  """

  alias Mehungry.FoodData.Usda.Parser.{Result, Token, Vocabulary}

  @spec vocabulary() :: Vocabulary.t()
  def vocabulary do
    Vocabulary.build(
      foods: [
        %{id: 1, name: "carrot", aliases: []},
        %{id: 2, name: "cucumber", aliases: []},
        %{id: 3, name: "corn", aliases: []},
        %{id: 4, name: "tomato", aliases: []},
        %{id: 5, name: "acerola", aliases: ["acerola cherry"]},
        %{id: 6, name: "spinach", aliases: []},
        %{id: 7, name: "chestnut", aliases: []},
        %{id: 8, name: "beef", aliases: []},
        %{id: 9, name: "milk", aliases: []},
        %{id: 10, name: "chicken breast", aliases: []}
      ],
      processing: [
        %{name: "raw", aliases: ["raw"]},
        %{
          name: "pickled",
          aliases: [
            %{alias: "pickle", head: true, implied_food: "cucumber", implied_food_id: 2},
            "pickled"
          ]
        },
        %{name: "oil", aliases: [%{alias: "oil", head: true}]},
        %{name: "puree", aliases: ["puree", "pureed"]},
        %{name: "juice", aliases: ["juice"]},
        %{name: "frozen", aliases: ["frozen"]},
        %{name: "dried", aliases: ["dried", "dehydrated"]},
        %{name: "roasted", aliases: ["roasted", "dry roasted"]},
        %{name: "boiled", aliases: ["boiled"]}
      ],
      harvest_stages: [
        %{name: "baby", aliases: ["young", "immature"]},
        %{name: "mature", aliases: []}
      ],
      parts: [
        %{name: "loin", aliases: []},
        %{name: "chuck", aliases: []}
      ],
      dismemberments: [
        %{name: "t bone steak", aliases: ["t-bone steak"]},
        %{name: "porterhouse steak", aliases: []},
        %{name: "top loin steak", aliases: []}
      ],
      packaging: [
        %{alias: "canned", packaging: "canned"},
        %{alias: "jarred", packaging: "canned"}
      ],
      descriptors: [
        %{alias: "alcoholic beverage", kind: "not_food"},
        %{alias: "alcohol", kind: "not_food"},
        %{alias: "dill", kind: "modifier"},
        %{alias: "kosher dill", kind: "modifier"},
        %{alias: "chopped", kind: "modifier"},
        %{alias: "leaf", kind: "modifier"},
        %{alias: "seed", kind: "modifier"},
        %{alias: "fruit", kind: "modifier"},
        %{alias: "european", kind: "modifier"},
        %{alias: "table", kind: "modifier"},
        %{alias: "red", kind: "modifier"},
        %{alias: "nfs", kind: "noise"},
        %{alias: "all varieties", kind: "noise"},
        %{alias: "boneless", kind: "bone_state"},
        %{alias: "bone in", kind: "bone_state"},
        %{alias: "lip on", kind: "bone_state"},
        %{alias: "meat only", kind: "portion"},
        %{alias: "skinless", kind: "portion"},
        %{alias: "separable lean only", kind: "portion"},
        %{alias: "separable lean and fat", kind: "portion"},
        %{alias: "choice", kind: "grade"},
        %{alias: "select", kind: "grade"},
        %{alias: "commercial", kind: "prepared"},
        %{alias: "commercially baked", kind: "prepared"}
      ]
    )
  end

  @doc "Builds a token for rule unit tests."
  @spec token(Token.type(), String.t(), keyword()) :: Token.t()
  def token(type, value, opts \\ []) do
    %Token{
      type: type,
      raw: Keyword.get(opts, :raw, value),
      value: value,
      segment: Keyword.get(opts, :segment, 0),
      position: Keyword.get(opts, :position, 0),
      meta: Keyword.get(opts, :meta, %{}),
      consumed: Keyword.get(opts, :consumed, false)
    }
  end

  @doc "Builds a classified result with positions assigned in token order."
  @spec result([Token.t()], keyword()) :: Result.t()
  def result(tokens, opts \\ []) do
    tokens =
      tokens
      |> Enum.with_index()
      |> Enum.map(fn {t, position} -> %{t | position: position} end)

    struct!(Result, Keyword.merge([tokens: tokens], opts))
  end
end
