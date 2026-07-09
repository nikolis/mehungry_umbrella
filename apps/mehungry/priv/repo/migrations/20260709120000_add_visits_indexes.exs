defmodule Mehungry.Repo.Migrations.AddVisitsIndexes do
  use Ecto.Migration

  def change do
    create index(:visits, [:inserted_at])
    create index(:visits, [:ip_address])
    create index(:visits, ["(details->>'path')"], name: :visits_details_path_index)
    create index(:visits, ["(details->>'referrer')"], name: :visits_details_referrer_index)
    create index(:visits, ["(details->>'user_id')"], name: :visits_details_user_id_index)
    create index(:visits, ["(details->>'visitor_id')"], name: :visits_details_visitor_id_index)
  end
end
