defmodule Mehungry.Repo.Migrations.AddPerLanguageSocialTargetsToAiBotConfigs do
  use Ecto.Migration

  def change do
    alter table(:ai_bot_configs) do
      # %{"en" => "page_id", "el" => "page_id"}
      add :facebook_page_ids, :map, default: %{}
      # %{"en" => "board_id", "el" => "board_id"}
      add :pinterest_board_ids, :map, default: %{}
    end
  end
end
