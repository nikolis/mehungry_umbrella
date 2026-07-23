defmodule Mehungry.Repo.Migrations.CreateTaxonomies do
  use Ecto.Migration

  def up do
    create table(:taxonomies) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :string

      timestamps()
    end

    create unique_index(:taxonomies, [:slug])

    create table(:taxonomy_nodes) do
      add :taxonomy_id, references(:taxonomies, on_delete: :delete_all), null: false
      add :parent_id, references(:taxonomy_nodes, on_delete: :delete_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, default: 0

      timestamps()
    end

    # UNIQUE(taxonomy_id, slug) rather than (taxonomy_id, parent_id, slug):
    # on PG14 NULL parent_id rows are never treated as duplicates
    # (NULLS NOT DISTINCT is PG15+). Slugs unique per taxonomy also let the
    # classifier identify a leaf by slug alone.
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
  end

  def down do
    drop table(:ingredient_taxonomy_nodes)
    drop table(:taxonomy_nodes)
    drop table(:taxonomies)
  end
end
