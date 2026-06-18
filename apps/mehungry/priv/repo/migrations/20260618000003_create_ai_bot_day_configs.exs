defmodule Mehungry.Repo.Migrations.CreateAiBotDayConfigs do
  use Ecto.Migration

  def change do
    create table(:ai_bot_day_configs) do
      add :bot_config_id, references(:ai_bot_configs, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :focus_hint, :string, null: false

      timestamps()
    end

    create index(:ai_bot_day_configs, [:bot_config_id])
    create unique_index(:ai_bot_day_configs, [:bot_config_id, :date])
  end
end
