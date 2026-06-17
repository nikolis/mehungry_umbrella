defmodule Mehungry.Repo.Migrations.CreateAiBotConfigs do
  use Ecto.Migration

  def change do
    create table(:ai_bot_configs) do
      add :theme, :string, null: false
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :bot_user_id, references(:users, on_delete: :restrict), null: false
      add :active, :boolean, default: true, null: false
      add :pinterest_default_board_id, :string
      add :publish_times, :map, default: %{}

      timestamps()
    end

    create unique_index(:ai_bot_configs, [:month, :year])
    create index(:ai_bot_configs, [:bot_user_id])
    create index(:ai_bot_configs, [:active])
  end
end
