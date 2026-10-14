defmodule Mehungry.Repo.Migrations.CreateBetaSignups do
  use Ecto.Migration

  def change do
    create table(:beta_signups) do
      add :email, :string, null: false
      add :canonical_email, :string, null: false
      add :unsubscribe_token, :string, null: false
      add :source, :string

      timestamps()
    end

    create unique_index(:beta_signups, [:canonical_email])
    create unique_index(:beta_signups, [:unsubscribe_token])
  end
end
