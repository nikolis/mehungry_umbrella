defmodule Mehungry.Food.FoundementalFoods do
  @moduledoc """
  Curation layer mapping USDA-backed ingredients onto a registry of
  fundamental food species (`FoundementalFoodSpecies`) via `FoundementalFood`
  join rows. Backs the admin USDA Schema view: an ingredient assigned to a
  species drops out of the "to classify" lists and reappears grouped under its
  species.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{FoundementalFood, FoundementalFoodSpecies}

  # ── Species ────────────────────────────────────────────────────────────────

  @doc "All species ordered by name (then variety)."
  def list_species do
    Repo.all(from s in FoundementalFoodSpecies, order_by: [asc: s.name, asc: s.variety])
  end

  @doc "Species with their curated `foundemental_foods` preloaded, name-ordered."
  def list_species_with_foods do
    Repo.all(
      from s in FoundementalFoodSpecies,
        order_by: [asc: s.name, asc: s.variety],
        preload: [foundemental_foods: ^from(f in FoundementalFood, order_by: [asc: f.usda_name])]
    )
  end

  def get_species!(id), do: Repo.get!(FoundementalFoodSpecies, id)

  def change_species(%FoundementalFoodSpecies{} = species, attrs \\ %{}) do
    FoundementalFoodSpecies.changeset(species, attrs)
  end

  def create_species(attrs) do
    %FoundementalFoodSpecies{}
    |> FoundementalFoodSpecies.changeset(attrs)
    |> Repo.insert()
  end

  # ── Foundemental foods (join rows) ───────────────────────────────────────────

  def create_foundemental_food(attrs) do
    %FoundementalFood{}
    |> FoundementalFood.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Assigns an ingredient to a species, snapshotting `usda_name`. Idempotent-ish:
  the unique index on `ingredient_id` prevents duplicate assignment.
  """
  def assign_ingredient(species_id, ingredient_id, usda_name) do
    create_foundemental_food(%{
      foundemental_species_id: species_id,
      ingredient_id: ingredient_id,
      usda_name: usda_name
    })
  end

  @doc "MapSet of ingredient ids already curated onto some species."
  def assigned_ingredient_ids do
    FoundementalFood
    |> select([f], f.ingredient_id)
    |> Repo.all()
    |> MapSet.new()
  end
end
