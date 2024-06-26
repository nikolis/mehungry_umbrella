defmodule Mehungry.Survey.Demographic.Query do
  @moduledoc false

  import Ecto.Query
  alias Mehungry.Survey.Demographic

  def base do
    Demographic
  end

  def for_user(query \\ base(), user) do
    query
    |> where([d], d.user_id == ^user.id)
  end
end
