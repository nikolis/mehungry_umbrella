defmodule Mehungry.Repo.Migrations.WidenPubtatorTextColumns do
  use Ecto.Migration

  # Follow-up to WidenCompoundTextColumns. That migration widened `compounds.name`
  # /`synonyms`, but the same `22001 string_data_right_truncation` trap is still
  # open on the other free-text columns the PubTator annotation path fills straight
  # from PubChem/PubTator — long IUPAC names and mention/entity surface text
  # routinely exceed 255 chars. Overflowing any one of them raises inside
  # `annotate_study/1`, which (before the worker's `safe_annotate/1` rescue) escaped
  # the poison-pill guard and wedged the whole run at 0/N until the job discarded —
  # the "annotation stuck even after restart" report.
  #
  # These are external free text with no reason to be capped; widen them to :text.
  def up do
    alter table(:pubchem_responses) do
      modify :requested_name, :text
    end

    alter table(:study_entity_mentions) do
      modify :text_span, :text
    end

    alter table(:study_entity_relations) do
      modify :entity1_name, :text
      modify :entity2_name, :text
    end
  end

  def down do
    alter table(:pubchem_responses) do
      modify :requested_name, :string
    end

    alter table(:study_entity_mentions) do
      modify :text_span, :string
    end

    alter table(:study_entity_relations) do
      modify :entity1_name, :string
      modify :entity2_name, :string
    end
  end
end
