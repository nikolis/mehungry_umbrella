defmodule Mehungry.Repo.Migrations.CreateProfessionalClients do
  use Ecto.Migration

  def change do
    create table(:professional_clients) do
      add :professional_id, references(:users, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :full_name, :string, null: false
      add :date_of_birth, :date
      add :email, :string
      add :phone, :string
      add :address, :string
      add :postal_code, :string
      add :work_schedule, :text

      timestamps()
    end

    create index(:professional_clients, [:professional_id])
    create index(:professional_clients, [:user_id])
  end
end
