defmodule Mehungry.Health.ConditionResolver do
  @moduledoc """
  Resolves a disease reference (as extracted by PubTator) to one of our seeded
  `Condition` rows — the disease-side analogue of `Chemistry.Resolver`, but purely
  local: we only care about diseases that match a condition we already track, so
  there is no external API call.

  Resolution is identifier-first, name/synonym second:

    1. `(namespace, identifier)` → `Health.get_condition_by_identifier/2`. A known
       MeSH id returns immediately.
    2. Otherwise the disease `name` is normalized and matched (case-insensitively)
       against each condition's `name` and `synonyms`. On a confident match, the
       `(namespace, identifier)` mapping is written to `condition_identifiers`
       (`source: "pubtator"`), so the *next* lookup is identifier-first.

  Returns `{:ok, %Condition{}}` or `{:error, :not_found}`. An unmatched disease is
  left unresolved (the relation keeps its raw string, `condition_id: nil`) rather
  than inventing a condition.

  Input is a map with any of `:namespace` + `:identifier` (the MeSH anchor) and/or
  `:name` (the surface/preferred term). `resolve_normalized/2` is a convenience for
  the `"mesh:D007249"` form stored on relations/mentions.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Health

  @doc "Resolve from a `\"mesh:D007249\"`-style identifier plus a fallback name."
  @spec resolve_normalized(String.t() | nil, String.t() | nil) ::
          {:ok, Mehungry.Health.Condition.t()} | {:error, :not_found}
  def resolve_normalized(normalized_identifier, name) do
    resolve(Map.merge(split_identifier(normalized_identifier), %{name: name}))
  end

  @doc "Resolve a disease reference map to a `Condition`."
  @spec resolve(map()) :: {:ok, Mehungry.Health.Condition.t()} | {:error, :not_found}
  def resolve(input) do
    namespace = input[:namespace] || input["namespace"]
    identifier = input[:identifier] || input["identifier"]
    name = input[:name] || input["name"]

    with nil <- by_identifier(namespace, identifier),
         nil <- by_name(name) do
      {:error, :not_found}
    else
      %Health.Condition{} = condition ->
        maybe_write_identifier(condition, namespace, identifier)
        {:ok, condition}
    end
  end

  # ── steps ────────────────────────────────────────────────────────────────

  defp by_identifier(namespace, identifier)
       when is_binary(namespace) and is_binary(identifier) do
    Health.get_condition_by_identifier(namespace, identifier)
  end

  defp by_identifier(_namespace, _identifier), do: nil

  defp by_name(name) when is_binary(name) do
    norm = normalize(name)

    cond do
      norm == "" -> nil
      hit = exact_match(norm) -> hit
      true -> token_set_match(name)
    end
  end

  defp by_name(_name), do: nil

  # Fast path: a case-insensitive exact match on the canonical name or a synonym.
  defp exact_match(norm) do
    Mehungry.Repo.one(
      from(c in Health.Condition,
        where:
          fragment("lower(btrim(?)) = ?", c.name, ^norm) or
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS s WHERE lower(btrim(s)) = ?)",
              c.synonyms,
              ^norm
            ),
        limit: 1
      )
    )
  end

  # Fallback: order-independent token-set *equality*. MeSH preferred terms are often
  # word-inverted ("Diabetes Mellitus Type 2" ↔ our "Type 2 Diabetes Mellitus"), which
  # exact matching misses. Requiring the full token set to be equal (not a subset)
  # keeps this conservative — bare "Diabetes Mellitus" never collides with a specific
  # "Type 2 Diabetes Mellitus". Only ~200 conditions, so scanning in memory is cheap.
  defp token_set_match(name) do
    target = token_set(name)

    if MapSet.size(target) == 0 do
      nil
    else
      Enum.find(Health.list_conditions(), &matches_token_set?(&1, target))
    end
  end

  defp matches_token_set?(condition, target) do
    [condition.name | condition.synonyms || []]
    |> Enum.any?(fn label -> token_set(label) == target end)
  end

  defp token_set(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  # Persist the identifier so subsequent resolutions are identifier-first. Only when
  # the id is in a namespace the schema accepts (mesh/icd…); ignore failures — the
  # resolution itself already succeeded.
  defp maybe_write_identifier(condition, namespace, identifier)
       when is_binary(namespace) and is_binary(identifier) do
    Health.upsert_condition_identifier(%{
      condition_id: condition.id,
      namespace: namespace,
      identifier: identifier,
      source: "pubtator"
    })
  end

  defp maybe_write_identifier(_condition, _namespace, _identifier), do: :ok

  # ── helpers ────────────────────────────────────────────────────────────────

  defp split_identifier(id) when is_binary(id) do
    case String.split(id, ":", parts: 2) do
      [namespace, identifier] -> %{namespace: String.downcase(namespace), identifier: identifier}
      _ -> %{}
    end
  end

  defp split_identifier(_), do: %{}

  defp normalize(name), do: name |> String.trim() |> String.downcase()
end
