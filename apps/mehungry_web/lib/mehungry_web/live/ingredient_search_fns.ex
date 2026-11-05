defmodule MehungryWeb.IngredientSearchFns do
  @moduledoc """
  Shared, locale-aware closures for the ingredient picker (`SelectComponentDeep`).

  Every ingredient picker — recipe creation and the calendar meal form — needs
  the same behaviour: when the UI locale is Greek, search translated ingredient
  names and label/resolve results by their Greek name; otherwise fall back to the
  English base-name search. Keeping that swap in one place means a new picker is
  locale-aware for free rather than re-hardcoding the English search.

  Returns `%{item_fn, label_fn, get_by_id_fn, icon_fn}`:
    * `item_fn.(term)` — search function feeding the dropdown
    * `label_fn.(item)` — how a result/selection is displayed
    * `get_by_id_fn.(id)` — resolves a selected id back to an item (name overlaid
      with its Greek translation in `"el"`)
    * `icon_fn.(items)` — a `%{id => emoji}` map for the result set, species-aware
      and locale-independent (derived from the English base name — see
      `Mehungry.Food.ingredient_icons/1`)
  """

  alias Mehungry.Food
  alias Mehungry.Food.IngredientSearch

  @doc """
  Build the picker closures for `language` (e.g. "en"/"el"), scoped to `owner_id`
  so a user's own ingredients are included.
  """
  def search_fns(language, owner_id)

  def search_fns("el", owner_id) do
    %{
      item_fn: fn term -> IngredientSearch.search_in_language(term, "el", owner_id) end,
      label_fn: fn item -> item.name end,
      get_by_id_fn: fn id ->
        ingredient = Food.get_ingredient!(id)

        case Food.find_ingredient_translation("el", id) do
          [greek_name | _] -> %{ingredient | name: greek_name}
          [] -> ingredient
        end
      end,
      icon_fn: &icon_map/1
    }
  end

  def search_fns(_language, owner_id) do
    %{
      item_fn: fn term -> IngredientSearch.search(term, [], owner_id) end,
      label_fn: fn item -> Mehungry.Utils.remove_parenthesis(item.name) end,
      get_by_id_fn: &Food.get_ingredient!/1,
      icon_fn: &icon_map/1
    }
  end

  # `%{ingredient_id => emoji}` for a result set. Works for both locales because
  # the emoji is resolved from each ingredient's id (English base name / species
  # override), not from the display label — see `Mehungry.Food.ingredient_icons/1`.
  defp icon_map(items), do: Food.ingredient_icons(Enum.map(items, & &1.id))
end
