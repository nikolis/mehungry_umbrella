defmodule Mehungry.Food.Recipe.Query do
  @moduledoc false

  import Ecto.Query

  alias Mehungry.Food.Recipe

  def base, do: Recipe
end
