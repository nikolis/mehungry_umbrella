defmodule MehungryServer.Repo.Migrations.CreateRecipes do
  use Ecto.Migration

  def change do
    create table(:recipes) do
      add :servings, :integer
      add :cousine, :string
      add :title, :string
      add :author, :string
      add :original_url, :string
      add :private, :boolean
      add :preperation_time_upper_limit, :integer
      add :preperation_time_lower_limit, :integer
      add :cooking_time_upper_limit, :integer
      add :cooking_time_lower_limit, :integer
      add :recipe_image_remote, :string
      add :description, :string
      add :image_url, :string
      add :user_id, references(:users, on_delete: :nothing)

      add :language_name,
          references(:languages, column: :name, type: :string, on_delete: :nothing)

      add :steps, {:array, :map}, default: []

      timestamps()
    end

    create index(:recipes, [:user_id])
    create unique_index(:recipes, [:title, :user_id], name: :title_user_index)
  end
end
