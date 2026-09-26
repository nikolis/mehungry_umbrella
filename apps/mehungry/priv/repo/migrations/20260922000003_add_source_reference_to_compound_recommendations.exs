defmodule Mehungry.Repo.Migrations.AddSourceReferenceToCompoundRecommendations do
  use Ecto.Migration

  # Structured citation for non-PubMed advice (manual / clinical guideline), so a
  # recommendation with no linked ScientificStudy still points the user at a real
  # source: %{"label" => _, "url" => _, "doi" => _, "pmid" => _}.
  def change do
    alter table(:compound_recommendations) do
      add :source_reference, :map
    end
  end
end
