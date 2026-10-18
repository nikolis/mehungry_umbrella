defmodule MehungryWeb.IngredientSearchFns do
  @moduledoc """
  Shared, locale-aware closures for the ingredient picker (`SelectComponentDeep`).

  Every ingredient picker — recipe creation and the calendar meal form — needs
  the same behaviour: when the UI locale is Greek, search translated ingredient
  names and label/resolve results by their Greek name; otherwise fall back to the
  English base-name search. Keeping that swap in one place means a new picker is
  locale-aware for free rather than re-hardcoding the English search.

  Returns `%{item_fn, label_fn, get_by_id_fn}`:
    * `item_fn.(term)` — search function feeding the dropdown
    * `label_fn.(item)` — how a result/selection is displayed
    * `get_by_id_fn.(id)` — resolves a selected id back to an item (name overlaid
      with its Greek translation in `"el"`)
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
      end
    }
  end

  def search_fns(_language, owner_id) do
    %{
      item_fn: fn term -> IngredientSearch.search(term, [], owner_id) end,
      label_fn: fn item -> Mehungry.Utils.remove_parenthesis(item.name) end,
      get_by_id_fn: &Food.get_ingredient!/1
    }
  end
end
