defmodule MehungryWeb.IngredientSearchFnsTest do
  @moduledoc """
  The picker closures expose an `icon_fn` that resolves a result set to
  `%{ingredient_id => emoji}` — the contract `SelectComponentDeep` relies on to
  show an emoji per option. It resolves from the English base name / species
  override, so it is identical across locales.
  """
  use MehungryWeb.ConnCase, async: true

  import Mehungry.FoodFixtures

  alias MehungryWeb.IngredientSearchFns

  test "search_fns/2 exposes an icon_fn mapping result ids to emojis" do
    tomato = ingredient_fixture(%{name: "Tomato, raw"})

    for language <- ["en", "el"] do
      fns = IngredientSearchFns.search_fns(language, nil)
      assert is_function(fns.icon_fn, 1)
      assert fns.icon_fn.([%{id: tomato.id}]) == %{tomato.id => "🍅"}
    end
  end
end
