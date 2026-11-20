defmodule Mehungry.Repo.Migrations.CreateShoppingBasketSharing do
  use Ecto.Migration

  # Shared shopping lists: the owner (shopping_baskets.user_id) invites other
  # people; accepted invitations become member rows. See
  # docs/features/shared_basket.md.
  def change do
    create table(:shopping_basket_members) do
      add :shopping_basket_id, references(:shopping_baskets, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:shopping_basket_members, [:shopping_basket_id, :user_id])
    create index(:shopping_basket_members, [:user_id])

    create table(:shopping_basket_invitations) do
      add :shopping_basket_id, references(:shopping_baskets, on_delete: :delete_all), null: false
      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      # Email the invite was addressed to, as typed (nil for a link-only invite).
      add :invitee_email, :string
      # Set when that email belongs to an existing account: lets the invitee
      # accept or decline from inside the app without the link.
      add :invitee_user_id, references(:users, on_delete: :delete_all)
      # SHA-256 of the single-use link token; the token itself is never stored.
      add :token_hash, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :accepted_by_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:shopping_basket_invitations, [:token_hash])
    create index(:shopping_basket_invitations, [:shopping_basket_id, :status])
    create index(:shopping_basket_invitations, [:invitee_user_id, :status])

    # Who added a line and who ticked it off, shown on shared lists.
    alter table(:basket_items) do
      add :added_by_id, references(:users, on_delete: :nilify_all)
      add :acquired_by_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:basket_ingredients) do
      add :added_by_id, references(:users, on_delete: :nilify_all)
      add :acquired_by_id, references(:users, on_delete: :nilify_all)
    end
  end
end
