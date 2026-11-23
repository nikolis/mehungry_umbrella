defmodule Mehungry.Repo.Migrations.AddTargetKcalToClientIntakes do
  use Ecto.Migration

  # The nutritionist's prescribed daily energy target, when they choose to
  # differ from the estimated TDEE (e.g. a deficit for weight loss). Nullable:
  # nil means "no prescription — plan to TDEE".
  def change do
    alter table(:client_intakes) do
      add :target_kcal, :integer
    end
  end
end
