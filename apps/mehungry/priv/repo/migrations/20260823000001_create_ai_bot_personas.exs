defmodule Mehungry.Repo.Migrations.CreateAiBotPersonas do
  use Ecto.Migration

  def change do
    create table(:ai_bot_personas) do
      add :name, :string, null: false
      add :archetype, :string
      add :description, :string
      # The system-prompt fragment: identity, priorities, quirks, how they talk.
      add :voice_prompt, :text, null: false
      add :uses_hashtags, :boolean, null: false, default: false
      add :default_origin, :string
      add :active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:ai_bot_personas, [:name])
  end
end
