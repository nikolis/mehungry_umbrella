defmodule Mehungry.Repo.Migrations.CreateTaxonomies do
  use Ecto.Migration

  def up do
    create table(:taxonomies) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text

      timestamps()
    end

    create unique_index(:taxonomies, [:slug])

    create table(:taxonomy_nodes) do
      add :taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false
      add :parent_id, references(:taxonomy_nodes, on_delete: :delete_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, default: 0, null: false

      timestamps()
    end

    # UNIQUE(taxonomy_id, parent_id, slug) would not catch duplicate roots on
    # PG14 (NULL parent_id rows are never equal), so slugs are unique per taxonomy.
    create unique_index(:taxonomy_nodes, [:taxonomy_id, :slug])
    create index(:taxonomy_nodes, [:parent_id])

    create table(:ingredient_taxonomy_nodes) do
      add :ingredient_id, references(:ingredients, on_delete: :delete_all), null: false
      add :taxonomy_node_id, references(:taxonomy_nodes, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :confidence, :float
      add :reviewed, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:ingredient_taxonomy_nodes, [:ingredient_id, :taxonomy_node_id])
    create index(:ingredient_taxonomy_nodes, [:taxonomy_node_id])
    create index(:ingredient_taxonomy_nodes, [:reviewed, :confidence])

    alter table(:categories) do
      add :usda_code, :string
    end
  end

  def down do
    alter table(:categories) do
      remove :usda_code
    end

    drop table(:ingredient_taxonomy_nodes)
    drop table(:taxonomy_nodes)
    drop table(:taxonomies)
  end
end
