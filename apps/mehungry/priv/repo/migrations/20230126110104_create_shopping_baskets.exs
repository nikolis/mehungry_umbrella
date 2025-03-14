defmodule Mehungry.Repo.Migrations.CreateShoppingBaskets do
  use Ecto.Migration

  def change do
    create table(:shopping_baskets) do
      add :start_dt, :naive_datetime
      add :end_dt, :naive_datetime
      add :user_id, references(:users, on_delete: :nothing)
      add :title, :string

      timestamps()
    end

    create index(:shopping_baskets, [:user_id])
    create unique_index(:shopping_baskets, [:title, :user_id])
  end
end
