defmodule Mehungry.Repo.Migrations.AddHandleToProfessionalProfiles do
  use Ecto.Migration

  def change do
    alter table(:professional_profiles) do
      # Short, user-chosen vanity handle for the personal short link `/@handle`.
      # Nullable — a null handle just means "no short link yet". Distinct from
      # `slug` (the stable, SEO-indexed canonical URL key).
      add :handle, :string
    end

    create unique_index(:professional_profiles, [:handle])
  end
end
