defmodule Mehungry.Languages.Translations do
  @moduledoc """
  Generic, descriptor-driven read/write operations over any `*_translation`
  table. Given a `Mehungry.Languages.TranslationRegistry` descriptor it can list
  base rows paired with their translation for a locale, upsert a translation
  (ISO write code, `status`/verification stamped), and flip a draft to verified —
  without any per-resource code. Powers the professional translation hub.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Languages
  alias Mehungry.Languages.Locale

  @default_limit 50

  @doc "Total number of base rows for a resource."
  def count_total(descriptor), do: Repo.aggregate(descriptor.base_schema, :count)

  @doc """
  List `%{base: base_row, translation: translation | nil}` pairs for a locale.

  Options: `:filter` (`:all` | `:missing` | `:ai_draft` | `:verified`),
  `:limit`, `:offset`.
  """
  def list_items(descriptor, locale, opts \\ []) do
    codes = Locale.data_codes(locale)
    filter = Keyword.get(opts, :filter, :all)
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    bases =
      descriptor
      |> base_query(codes, filter)
      |> order_by([b], asc: b.id)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    ids = Enum.map(bases, & &1.id)
    tmap = translations_map(descriptor, codes, ids)

    Enum.map(bases, fn base -> %{base: base, translation: Map.get(tmap, base.id)} end)
  end

  @doc "Count base rows matching a filter (for pagination)."
  def count_items(descriptor, locale, filter) do
    codes = Locale.data_codes(locale)

    descriptor
    |> base_query(codes, filter)
    |> Repo.aggregate(:count)
  end

  @doc """
  All base-row ids that still lack a translation for a locale. `:limit` caps the
  result (used to bound a bulk AI-translate run).
  """
  def missing_ids(descriptor, locale, opts \\ []) do
    codes = Locale.data_codes(locale)

    query =
      descriptor
      |> base_query(codes, :missing)
      |> select([b], b.id)

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end

  @doc "Load a single base row and its preferred translation for a locale."
  def get_pair(descriptor, base_id, locale) do
    codes = Locale.data_codes(locale)
    base = Repo.get(descriptor.base_schema, base_id)
    translation = base && preferred_translation(descriptor, codes, base_id)
    %{base: base, translation: translation}
  end

  @doc """
  Upsert the translation for `(base_id, locale)`.

  `field_values` is a map of the descriptor's translatable fields to translated
  text. Options: `:status` (`"verified"` default | `"ai_draft"`) and
  `:verified_by_id`. On `"verified"` the verification audit fields are stamped.
  Writes under the locale's canonical ISO code.
  """
  def upsert(descriptor, base_id, locale, field_values, opts \\ []) do
    status = Keyword.get(opts, :status, "verified")
    write_code = Locale.write_code(locale)
    Languages.ensure_language(write_code)

    attrs =
      field_values
      |> Map.new(fn {k, v} -> {k, v} end)
      |> Map.put(descriptor.fk, base_id)
      |> Map.put(:language_name, write_code)
      |> Map.put(:status, status)
      |> stamp_verification(status, opts)

    struct =
      get_translation(descriptor, base_id, write_code) ||
        struct(descriptor.translation_schema)

    struct
    |> descriptor.translation_schema.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Mark the existing translation for `(base_id, locale)` verified."
  def verify(descriptor, base_id, locale, opts \\ []) do
    codes = Locale.data_codes(locale)

    case preferred_translation(descriptor, codes, base_id) do
      nil ->
        {:error, :not_found}

      translation ->
        attrs = stamp_verification(%{status: "verified"}, "verified", opts)

        translation
        |> descriptor.translation_schema.changeset(attrs)
        |> Repo.update()
    end
  end

  # ── internals ──────────────────────────────────────────────────────────────

  defp stamp_verification(attrs, "verified", opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put(:verified_at, now)
    |> Map.put(:verified_by_id, Keyword.get(opts, :verified_by_id))
  end

  defp stamp_verification(attrs, _status, _opts), do: attrs

  defp base_query(descriptor, _codes, :all), do: from(b in descriptor.base_schema)

  defp base_query(descriptor, codes, :missing) do
    sub = translated_ids_query(descriptor, codes, nil)
    from(b in descriptor.base_schema, where: b.id not in subquery(sub))
  end

  defp base_query(descriptor, codes, status) when status in [:ai_draft, :verified] do
    sub = translated_ids_query(descriptor, codes, Atom.to_string(status))
    from(b in descriptor.base_schema, where: b.id in subquery(sub))
  end

  defp translated_ids_query(descriptor, codes, nil) do
    fk = descriptor.fk

    from(t in descriptor.translation_schema,
      where: t.language_name in ^codes,
      select: field(t, ^fk)
    )
  end

  defp translated_ids_query(descriptor, codes, status) do
    fk = descriptor.fk

    from(t in descriptor.translation_schema,
      where: t.language_name in ^codes and t.status == ^status,
      select: field(t, ^fk)
    )
  end

  defp translations_map(_descriptor, _codes, []), do: %{}

  defp translations_map(descriptor, codes, ids) do
    fk = descriptor.fk

    from(t in descriptor.translation_schema,
      where: t.language_name in ^codes and field(t, ^fk) in ^ids
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn t, acc ->
      key = Map.get(t, fk)

      case Map.get(acc, key) do
        nil -> Map.put(acc, key, t)
        existing -> if prefer?(t, existing, codes), do: Map.put(acc, key, t), else: acc
      end
    end)
  end

  # Prefer the row whose code is earlier in `codes` (ISO canonical over legacy).
  defp prefer?(candidate, existing, codes) do
    rank(candidate.language_name, codes) < rank(existing.language_name, codes)
  end

  defp rank(code, codes) do
    Enum.find_index(codes, &(&1 == code)) || length(codes)
  end

  defp preferred_translation(descriptor, codes, base_id) do
    fk = descriptor.fk

    rows =
      from(t in descriptor.translation_schema,
        where: t.language_name in ^codes and field(t, ^fk) == ^base_id
      )
      |> Repo.all()

    case rows do
      [] -> nil
      rows -> Enum.min_by(rows, &rank(&1.language_name, codes))
    end
  end

  defp get_translation(descriptor, base_id, code) do
    Repo.get_by(descriptor.translation_schema, [{descriptor.fk, base_id}, {:language_name, code}])
  end
end
