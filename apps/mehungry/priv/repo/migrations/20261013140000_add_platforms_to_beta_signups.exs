defmodule Mehungry.Repo.Migrations.AddPlatformsToBetaSignups do
  use Ecto.Migration

  def change do
    # Platforms a tester is interested in. Adding a NOT NULL column with a
    # default backfills existing rows (registered before this field) to "all".
    alter table(:beta_signups) do
      add :platforms, {:array, :string}, null: false, default: ["android", "ios", "web"]
    end
  end
end
