defmodule Mehungry.Social.Instagram.CaptionTest do
  use ExUnit.Case, async: true

  alias Mehungry.Social.Instagram.Caption

  @max_length 2200

  defp recipe(attrs \\ %{}) do
    Map.merge(
      %{
        title: "Greek Salad",
        description: "A fresh summer salad",
        recipe_ingredients: [
          %{
            quantity: 2,
            measurement_unit: %{name: "pieces"},
            ingredient: %{name: "tomato"}
          },
          %{
            quantity: 0.5,
            measurement_unit: %{name: "cup"},
            ingredient: %{name: "olive oil"}
          }
        ],
        steps: [%{title: "Chop", description: "Chop everything"}],
        nutrients: %{
          "protein" => %{"name" => "Protein", "amount" => 5, "measurement_unit" => "g"}
        }
      },
      attrs
    )
  end

  describe "format_number/1" do
    test "handles integers, floats, whole floats, and nil" do
      assert Caption.format_number(5) == "5"
      assert Caption.format_number(5.0) == "5"
      assert Caption.format_number(5.678) == "5.68"
      assert Caption.format_number(nil) == ""
    end
  end

  describe "build/1" do
    test "includes all sections and the hashtag" do
      caption = Caption.build(recipe())

      assert caption =~ "Greek Salad"
      assert caption =~ "Ingredients"
      assert caption =~ "2 pieces tomato"
      assert caption =~ "0.5 cup olive oil"
      assert caption =~ "Instructions"
      assert caption =~ "Nutrients"
      assert caption =~ "Protein 5 g"
      assert String.ends_with?(caption, "#m3hungry")
    end

    test "integer nutrient amounts do not crash (legacy Float.to_string bug)" do
      caption =
        recipe(%{
          nutrients: %{"kcal" => %{"name" => "Energy", "amount" => 250, "measurement_unit" => "kcal"}}
        })
        |> Caption.build()

      assert caption =~ "Energy 250 kcal"
    end

    test "drops trailing sections to stay within the limit" do
      long_steps =
        for i <- 1..40, do: %{title: "Step #{i}", description: String.duplicate("cook ", 20)}

      caption = Caption.build(recipe(%{steps: long_steps}))

      assert String.length(caption) <= @max_length
      assert String.ends_with?(caption, "#m3hungry")
      refute caption =~ "Nutrients"
    end

    test "hard-truncates when even header + ingredients exceed the limit" do
      caption = Caption.build(recipe(%{description: String.duplicate("very tasty ", 300)}))

      assert String.length(caption) <= @max_length
      assert String.ends_with?(caption, "#m3hungry")
    end

    test "tolerates missing optional fields" do
      caption =
        Caption.build(%{
          title: "Bare",
          description: nil,
          recipe_ingredients: [],
          steps: nil,
          nutrients: nil
        })

      assert caption == "Bare\n\n#m3hungry"
    end
  end
end
