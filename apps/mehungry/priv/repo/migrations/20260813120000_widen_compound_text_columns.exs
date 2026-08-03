defmodule Mehungry.Repo.Migrations.WidenCompoundTextColumns do
  use Ecto.Migration

  # PubTator chemicals resolve against PubChem, whose canonical/IUPAC names and
  # synonyms frequently exceed 255 chars. Inserting one raised `22001
  # string_data_right_truncation` in `Chemistry.Resolver.upsert_compound`, which
  # aborted the whole study before its annotation attempt was ledgered — so every
  # PubTatorAnnotationWorker retry re-picked the same poison study and the run
  # stalled at 0/N until the job was discarded. Same fix as
  # WidenScientificStudyTextColumns: these are free-text with no reason to be capped.
  def up do
    alter table(:compounds) do
      modify :name, :text
      modify :synonyms, {:array, :text}
    end
  end

  def down do
    alter table(:compounds) do
      modify :name, :string
      modify :synonyms, {:array, :string}
    end
  end
end
