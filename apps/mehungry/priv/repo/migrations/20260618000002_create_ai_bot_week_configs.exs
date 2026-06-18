defmodule Mehungry.Repo.Migrations.CreateAiBotWeekConfigs do
  use Ecto.Migration

  def change do
    create table(:ai_bot_week_configs) do
      add :bot_config_id, references(:ai_bot_configs, on_delete: :delete_all), null: false
      add :week_number, :integer, null: false
      add :theme, :string, null: false

      timestamps()
    end

    create index(:ai_bot_week_configs, [:bot_config_id])
    create unique_index(:ai_bot_week_configs, [:bot_config_id, :week_number])
  end
end
