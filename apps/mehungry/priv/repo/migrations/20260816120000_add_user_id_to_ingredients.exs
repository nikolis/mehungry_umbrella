defmodule Mehungry.Repo.Migrations.AddUserIdToIngredients do
  use Ecto.Migration

  def up do
    alter table(:ingredients) do
      add :user_id, references(:users, on_delete: :delete_all)
    end

    create index(:ingredients, [:user_id])

    # The old global unique index on name breaks per-user duplicates. Replace it
    # with two partial unique indexes: global names (user_id IS NULL) stay unique
    # across the shared catalog, and each user's own names are unique per user.
    drop_if_exists unique_index(:ingredients, [:name])

    create unique_index(:ingredients, [:name],
             where: "user_id IS NULL",
             name: :ingredients_global_name_index
           )

    create unique_index(:ingredients, [:user_id, :name],
             where: "user_id IS NOT NULL",
             name: :ingredients_user_name_index
           )
  end

  def down do
    drop_if_exists unique_index(:ingredients, [:user_id, :name], name: :ingredients_user_name_index)
    drop_if_exists unique_index(:ingredients, [:name], name: :ingredients_global_name_index)

    create unique_index(:ingredients, [:name])

    drop index(:ingredients, [:user_id])

    alter table(:ingredients) do
      remove :user_id
    end
  end
end
