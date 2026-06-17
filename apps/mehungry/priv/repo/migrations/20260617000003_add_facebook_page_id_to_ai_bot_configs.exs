defmodule Mehungry.Repo.Migrations.AddFacebookPageIdToAiBotConfigs do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_configs) do
      add :facebook_page_id, :string, null: true
    end
  end
end
