defmodule Mehungry.Repo.Migrations.MergeSynonymousConditionStates do
  use Ecto.Migration

  # One-off cleanup: before disease-state labels were canonicalized, synonymous phases
  # could be materialized as separate `ConditionState` rows for the same condition
  # (e.g. "flare" alongside "Active Flare"). Merge each such group into one keeper,
  # repointing its recommendations + candidates (rekeying their `dedup_key`, dropping
  # any that would collide with the keeper's own rows) and deleting the duplicates.
  #
  # The synonym set is inlined (not read from app code) so the migration stays stable
  # even if `Mehungry.Health.ClaimRules` changes later. Keep it in sync if the app's
  # synonym map grows.
  @synonyms %{
    "flare" => "active flare",
    "flares" => "active flare",
    "active" => "active flare",
    "active flare" => "active flare",
    "active flares" => "active flare",
    "active disease" => "active flare",
    "active diseases" => "active flare"
  }

  def up do
    repo = repo()

    %{rows: rows} =
      repo.query!("SELECT id, condition_id, name, is_default FROM condition_states ORDER BY id")

    rows
    |> Enum.map(fn [id, condition_id, name, is_default] ->
      %{id: id, condition_id: condition_id, name: name, is_default: is_default}
    end)
    |> Enum.group_by(fn s -> {s.condition_id, phase_key(s.name)} end)
    |> Enum.each(fn {_key, group} ->
      if length(group) > 1 do
        # Keep the default phase if any, else the oldest (lowest id); merge the rest.
        keeper = Enum.min_by(group, fn s -> {if(s.is_default, do: 0, else: 1), s.id} end)

        group
        |> Enum.reject(&(&1.id == keeper.id))
        |> Enum.each(&merge_state(repo, &1.id, keeper.id))
      end
    end)
  end

  # Irreversible data merge.
  def down, do: :ok

  defp merge_state(repo, dup_id, keeper_id) do
    move_rows(repo, "condition_state_recommendations", dup_id, keeper_id)
    move_rows(repo, "condition_recommendation_candidates", dup_id, keeper_id)
    repo.query!("DELETE FROM condition_states WHERE id = $1", [dup_id])
  end

  # Repoint a table's rows from dup_id to keeper_id, rekeying their `dedup_key`;
  # drop any row that would collide with a row the keeper already has.
  defp move_rows(repo, table, dup_id, keeper_id) do
    %{rows: rows} =
      repo.query!("SELECT id, dedup_key FROM #{table} WHERE condition_state_id = $1", [dup_id])

    Enum.each(rows, fn [id, dedup_key] ->
      new_key = rekey(dedup_key, keeper_id)

      %{rows: clash} =
        repo.query!(
          "SELECT 1 FROM #{table} WHERE dedup_key = $1 AND id <> $2 LIMIT 1",
          [new_key, id]
        )

      if clash == [] do
        repo.query!(
          "UPDATE #{table} SET condition_state_id = $1, dedup_key = $2 WHERE id = $3",
          [keeper_id, new_key, id]
        )
      else
        repo.query!("DELETE FROM #{table} WHERE id = $1", [id])
      end
    end)
  end

  # dedup_key is "condition_id|state_id|target[|source]" — swap the state segment.
  defp rekey(nil, _keeper_id), do: nil

  defp rekey(dedup_key, keeper_id) do
    case String.split(dedup_key, "|") do
      [condition, _state | rest] -> Enum.join([condition, to_string(keeper_id) | rest], "|")
      _ -> dedup_key
    end
  end

  # The canonical phase of a state name (synonyms folded, normalized), for grouping.
  defp phase_key(nil), do: ""

  defp phase_key(name) do
    norm = name |> String.trim() |> String.downcase()
    Map.get(@synonyms, norm, norm)
  end
end
