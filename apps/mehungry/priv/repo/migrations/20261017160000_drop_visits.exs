defmodule Mehungry.Repo.Migrations.DropVisits do
  use Ecto.Migration

  # The per-visit tracking table is removed: it only ever backed server-side
  # analytics that duplicated Google Analytics (traffic sources, page views,
  # device/OS, session reconstruction, SEO referrer reports) less accurately and
  # only for cookie-consented, LiveView traffic. GA4 + Search Console own all of
  # that now. The consent-independent denominator lives in daily_session_metrics,
  # which is untouched.
  def up do
    drop table(:visits)
  end

  def down do
    create table(:visits) do
      add :ip_address, :string
      add :session_key, :string
      add :details, :map

      timestamps()
    end

    create index(:visits, [:inserted_at])
    create index(:visits, [:ip_address])
    create index(:visits, ["(details->>'path')"], name: :visits_details_path_index)
    create index(:visits, ["(details->>'referrer')"], name: :visits_details_referrer_index)
    create index(:visits, ["(details->>'user_id')"], name: :visits_details_user_id_index)
    create index(:visits, ["(details->>'visitor_id')"], name: :visits_details_visitor_id_index)
  end
end
