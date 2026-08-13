defmodule Mehungry.Languages.Coverage do
  @moduledoc """
  Translation-coverage aggregate over every resource in
  `Mehungry.Languages.TranslationRegistry`. For each resource × target locale it
  reports how many base rows are verified / machine-drafted / still missing, plus
  a verified percentage — the numbers that drive the professional translation hub
  (e.g. "Ingredients EL: verified 62% · draft 15% · missing 23%").

  A base row counts as **verified** if it has any verified translation, as
  **ai_draft** if it has a draft but no verified translation, else **missing**.
  Both ISO and legacy `languages.name` codes are counted (see
  `Mehungry.Languages.Locale`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Languages.{Locale, Translations, TranslationRegistry}

  @doc """
  Coverage for every resource × target locale, as a list of maps:
  `%{key, label, language, total, verified, ai_draft, missing, pct}`.
  """
  def stats do
    for descriptor <- TranslationRegistry.all(),
        locale <- Locale.targets() do
      coverage(descriptor, locale)
    end
  end

  @doc "Coverage rows for a single resource (one per target locale)."
  def for_resource(descriptor) do
    Enum.map(Locale.targets(), &coverage(descriptor, &1))
  end

  @doc "Coverage for a single resource + locale."
  def coverage(descriptor, locale) do
    codes = Locale.data_codes(locale)
    total = Translations.count_total(descriptor)
    verified = count_verified(descriptor, codes)
    ai_draft = count_draft_only(descriptor, codes)
    missing = max(total - verified - ai_draft, 0)

    %{
      key: descriptor.key,
      label: descriptor.label,
      language: locale,
      total: total,
      verified: verified,
      ai_draft: ai_draft,
      missing: missing,
      pct: percent(verified, total)
    }
  end

  defp count_verified(descriptor, codes) do
    fk = descriptor.fk

    from(t in descriptor.translation_schema,
      where: t.language_name in ^codes and t.status == "verified",
      select: count(field(t, ^fk), :distinct)
    )
    |> Repo.one() || 0
  end

  # Bases with a draft translation but no verified translation.
  defp count_draft_only(descriptor, codes) do
    fk = descriptor.fk

    verified_ids =
      from(t in descriptor.translation_schema,
        where: t.language_name in ^codes and t.status == "verified",
        select: field(t, ^fk)
      )

    from(t in descriptor.translation_schema,
      where:
        t.language_name in ^codes and t.status == "ai_draft" and
          field(t, ^fk) not in subquery(verified_ids),
      select: count(field(t, ^fk), :distinct)
    )
    |> Repo.one() || 0
  end

  defp percent(_verified, 0), do: 0
  defp percent(verified, total), do: round(verified * 100 / total)
end
