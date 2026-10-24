defmodule Mehungry.Repo.Migrations.CreateRecipeSocialGraphics do
  use Ecto.Migration

  def change do
    create table(:recipe_social_graphics) do
      add :recipe_id, references(:recipes, on_delete: :delete_all), null: false
      add :image_url, :string, null: false
      add :insight_type, :string, null: false
      add :headline, :string
      add :caption, :text

      timestamps(updated_at: false)
    end

    create index(:recipe_social_graphics, [:recipe_id])
  end
end
