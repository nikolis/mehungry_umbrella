defmodule Mehungry.Repo.Migrations.UniqueUserFollows do
  use Ecto.Migration

  def up do
    # Collapse any pre-existing duplicate follow rows (no unique index existed
    # before), keeping the earliest row per (user_id, follow_id) pair.
    execute("""
    DELETE FROM user_follows a
    USING user_follows b
    WHERE a.user_id = b.user_id
      AND a.follow_id = b.follow_id
      AND a.id > b.id
    """)

    create unique_index(:user_follows, [:user_id, :follow_id])
  end

  def down do
    drop unique_index(:user_follows, [:user_id, :follow_id])
  end
end
