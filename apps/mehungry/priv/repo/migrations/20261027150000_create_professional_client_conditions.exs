defmodule Mehungry.Repo.Migrations.CreateProfessionalClientConditions do
  use Ecto.Migration

  def change do
    create table(:professional_client_conditions) do
      add :professional_client_id,
          references(:professional_clients, on_delete: :delete_all),
          null: false

      add :condition_id, references(:conditions, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:professional_client_conditions, [:professional_client_id])
    create index(:professional_client_conditions, [:condition_id])

    # A client can carry a given condition once — adding it twice is a no-op.
    create unique_index(:professional_client_conditions, [:professional_client_id, :condition_id],
             name: :professional_client_conditions_unique_index
           )
  end
end
