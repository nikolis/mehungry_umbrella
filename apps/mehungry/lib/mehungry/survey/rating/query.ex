defmodule Mehungry.Survey.Rating.Query do
  @moduledoc false

  import Ecto.Query
  alias Mehungry.Survey.Rating

  def base do
    Rating
  end

  def preload_user(user) do
    base()
    |> for_user(user)
  end

  defp for_user(query, user) do
    query
    |> where([r], r.user_id == ^user.id)
  end
end
