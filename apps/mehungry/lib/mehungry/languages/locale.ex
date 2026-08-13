defmodule Mehungry.Languages.Locale do
  @moduledoc """
  Core-side source of truth for content-locale codes, mirroring
  `MehungryWeb.Locale` (which lives in the web app and cannot be depended on
  from core). Bridges the historical split between ISO codes used in URLs /
  newer translation rows (`en`/`el`) and the legacy `languages` names used by
  older translation rows (`En`/`Gr`).

  New translation rows are written under the **ISO** code (`data_codes/1` returns
  the ISO code first, and `write_code/1` returns it). Coverage reads **both** the
  ISO and legacy codes so pre-existing legacy rows still count.
  """

  @locales ["en", "el"]
  @source "en"

  # locale => [canonical ISO code, ...legacy aliases]. First element is the
  # canonical write code; the rest are read-only back-compat aliases.
  @data_codes %{
    "en" => ["en", "En"],
    "el" => ["el", "Gr"]
  }

  @labels %{"en" => "English", "el" => "Greek"}

  @doc "All supported content locales (ISO), source first."
  def locales, do: @locales

  @doc "The source/base locale — content is authored in this language."
  def source, do: @source

  @doc "Locales we translate *into* (everything but the source)."
  def targets, do: @locales -- [@source]

  @doc "Every `languages.name` code that maps to this locale (ISO + legacy)."
  def data_codes(locale), do: Map.get(@data_codes, locale, [locale])

  @doc "The canonical code new rows are written under for this locale (ISO)."
  def write_code(locale), do: hd(data_codes(locale))

  @doc "Human-readable language name for a locale."
  def label(locale), do: Map.get(@labels, locale, locale)

  @doc "True if `locale` is a supported content locale."
  def supported?(locale), do: locale in @locales
end
