defmodule Mehungry.MealBlueprints.UserBlueprint do
  @moduledoc """
  Join row marking a blueprint a user has **saved** to their profile — the
  blueprint analogue of `Mehungry.Accounts.UserRecipe`. A regular user saves a
  public blueprint they discovered while browsing; it then shows up under their
  profile and in the calendar's "use a blueprint" picker.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.MealBlueprints.Blueprint

  schema "user_blueprints" do
    belongs_to :user, User
    belongs_to :blueprint, Blueprint

    timestamps()
  end

  @doc false
  def changeset(user_blueprint, attrs) do
    user_blueprint
    |> cast(attrs, [:user_id, :blueprint_id])
    |> validate_required([:user_id, :blueprint_id])
    |> unique_constraint([:user_id, :blueprint_id])
  end
end
