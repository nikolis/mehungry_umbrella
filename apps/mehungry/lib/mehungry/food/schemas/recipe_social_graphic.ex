defmodule Mehungry.Food.RecipeSocialGraphic do
  @moduledoc """
  A shareable social-media graphic generated for a recipe: the recipe's photo
  composited with a deterministic insight overlay (macro pie + a "Rich in X" /
  condition badge), plus the AI-written `headline` (shown on the graphic) and
  `caption` (social post copy).

  One recipe may have several over time (regeneration / variants); the newest
  row is what the share UI offers. `insight_type` records which characteristic
  was chosen (e.g. `"compound"`, `"health"`, `"macro"`, `"balanced"`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Food.Recipe

  schema "recipe_social_graphics" do
    field :image_url, :string
    field :insight_type, :string
    field :headline, :string
    field :caption, :string

    belongs_to :recipe, Recipe

    timestamps(updated_at: false)
  end

  def changeset(graphic, attrs) do
    graphic
    |> cast(attrs, [:recipe_id, :image_url, :insight_type, :headline, :caption])
    |> validate_required([:recipe_id, :image_url, :insight_type])
    |> foreign_key_constraint(:recipe_id)
  end
end
