defmodule Mehungry.Food.RecipeHashtag do
  @moduledoc """
  Hash tag str.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "recipe_hashtags" do
    field :temp_id, :string, virtual: true

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :hashtag, Mehungry.Hashtag
  end

  @doc false
  def changeset(recipe_ingredient, attrs) do
    recipe_ingredient
    # attrs = get_hashtags(attrs)
    # So its persisted
    |> cast(attrs, [
      :recipe_id,
      :hashtag_id,
      :temp_id
    ])
    |> validate_required([])
    |> foreign_key_constraint(:hashtag_id)
    |> foreign_key_constraint(:recipe_id)
    |> cast_assoc(:hashtag, required: true)
    |> maybe_mark_for_deletion()
  end

  defp maybe_mark_for_deletion(%{data: %{id: nil}} = changeset), do: changeset

  defp maybe_mark_for_deletion(changeset) do
    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
