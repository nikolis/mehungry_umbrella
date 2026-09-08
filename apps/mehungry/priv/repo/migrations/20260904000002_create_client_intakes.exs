defmodule Mehungry.Repo.Migrations.CreateClientIntakes do
  use Ecto.Migration

  def change do
    create table(:client_intakes) do
      add :professional_client_id,
          references(:professional_clients, on_delete: :delete_all),
          null: false

      add :assessed_on, :date
      add :height_m, :float
      add :weight_kg, :float
      add :bmi, :float
      add :usual_weight_kg, :float
      add :ideal_weight_kg, :float
      add :adjusted_weight_kg, :float
      add :bmr_kcal, :integer
      add :tdee_kcal, :integer
      add :goal, :text
      add :details, :map, default: %{}

      timestamps()
    end

    create index(:client_intakes, [:professional_client_id])
  end
end
