defmodule :"Elixir.Mehungry.Repo.Migrations.UserUser-userPostConnectionTables" do
  use Ecto.Migration

  def change do
    create table(:user_follows) do
      add :user_id, references(:users, on_delete: :delete_all)
      add :follow_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create table(:user_posts) do
      add :post_id, references(:posts, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create index(:user_follows, [:follow_id])
    create index(:user_follows, [:user_id])

    create index(:user_posts, [:post_id])
    create index(:user_posts, [:user_id])

  end
end
