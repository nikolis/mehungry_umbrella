defmodule Mehungry.Repo.Migrations.CreateModeration do
  use Ecto.Migration

  # User-generated-content moderation (App Store Guideline 1.2): reports filed
  # against a recipe / comment / user, and one-way user blocks.
  def change do
    create table(:content_reports) do
      # Kept when the reporter deletes their account — the report stays, unattributed.
      add :reporter_id, references(:users, on_delete: :nilify_all)
      add :target_type, :string, null: false
      add :target_id, :bigint, null: false
      # The author of the reported content (or the reported user).
      add :target_user_id, references(:users, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :note, :text
      # The reported text as it was when reported, so an edit or delete does not
      # erase the evidence.
      add :snapshot, :text
      add :status, :string, null: false, default: "open"
      add :resolution, :string
      add :admin_note, :text
      add :resolved_at, :naive_datetime

      timestamps()
    end

    create index(:content_reports, [:status, :inserted_at])
    create index(:content_reports, [:target_user_id])
    create index(:content_reports, [:target_type, :target_id])

    # One open report per reporter and target; a resolved one may be re-filed.
    create unique_index(:content_reports, [:reporter_id, :target_type, :target_id],
             where: "status = 'open'",
             name: :content_reports_open_unique_index
           )

    create table(:user_blocks) do
      add :blocker_id, references(:users, on_delete: :delete_all), null: false
      add :blocked_id, references(:users, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:user_blocks, [:blocker_id, :blocked_id])
    create index(:user_blocks, [:blocked_id])

    create constraint(:user_blocks, :user_blocks_no_self_block, check: "blocker_id <> blocked_id")
  end
end
