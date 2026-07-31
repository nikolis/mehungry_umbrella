defmodule Mehungry.Food.ParserProcessingMethod do
  @moduledoc """
  A canonical processing method of the USDA description parser ("pickled",
  "oil", "raw"). The name becomes the `processing` atom on parse results.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "parser_processing_methods" do
    field :name, :string

    has_many :aliases, Mehungry.Food.ParserProcessingAlias, foreign_key: :processing_method_id

    timestamps()
  end

  def changeset(method, attrs) do
    method
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
