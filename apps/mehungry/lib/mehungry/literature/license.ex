defmodule Mehungry.Literature.License do
  @moduledoc """
  Reuse-license vocabulary for PMC full text.

  Most articles in PubMed Central are **not** freely redistributable — only the Open
  Access subset is, and even that mixes commercial-OK (`CC0`, `CC BY`, `CC BY-SA`) with
  non-commercial / no-derivatives licenses (`CC BY-NC`, `CC BY-NC-ND`, …). Because the
  product is commercial, only the commercial-OK set may be displayed **verbatim**.

  This module normalizes the many spellings a JATS `<license>` / Europe PMC metadata
  field uses into a small canonical vocabulary and answers the one question the reader
  gate needs: `reusable?/1`.

  Canonical values: `"cc0"`, `"cc-by"`, `"cc-by-sa"`, `"cc-by-nc"`, `"cc-by-nc-sa"`,
  `"cc-by-nd"`, `"cc-by-nc-nd"`, `"other"`, `"unknown"`.
  """

  # Canonical license strings this product displays verbatim (commercial reuse OK).
  @reusable ~w(cc0 cc-by cc-by-sa)

  @all ~w(cc0 cc-by cc-by-sa cc-by-nc cc-by-nc-sa cc-by-nd cc-by-nc-nd other unknown)

  @doc "Every canonical license value."
  def all, do: @all

  @doc "The canonical values whose verbatim full text may be displayed commercially."
  def reusable_licenses, do: @reusable

  @doc """
  Normalize a free-text license label (JATS `license-type`, a CC deed URL, or Europe
  PMC's `license` field) to one canonical value. `nil`/blank/unrecognized → `"unknown"`;
  a recognized-but-non-CC label → `"other"`.

      iex> normalize("CC BY")       #=> "cc-by"
      iex> normalize("cc-by-nc-nd") #=> "cc-by-nc-nd"
      iex> normalize("https://creativecommons.org/licenses/by/4.0/") #=> "cc-by"
      iex> normalize(nil)           #=> "unknown"
  """
  def normalize(nil), do: "unknown"

  def normalize(raw) when is_binary(raw) do
    s = raw |> String.downcase() |> String.trim()

    cond do
      s == "" -> "unknown"
      # URL or text mentioning a CC license → classify by its clause tokens.
      String.contains?(s, "creativecommons.org") or String.contains?(s, "cc ") or
        String.starts_with?(s, "cc-") or String.starts_with?(s, "cc0") or
          s in ~w(by by-sa by-nc by-nc-sa by-nd by-nc-nd) ->
        classify_cc(s)

      # Public-domain dedications.
      s =~ ~r/\bpublic[\s\-]?domain\b/ or s =~ ~r/\bcc[\s\-]?0\b/ or String.contains?(s, "/zero/") ->
        "cc0"

      true ->
        "other"
    end
  end

  def normalize(_), do: "unknown"

  # Decide a CC variant from the clause tokens present (nc, nd, sa). Order matters:
  # the most-restrictive combination wins.
  defp classify_cc(s) do
    cond do
      s =~ ~r/\bcc[\s\-]?0\b/ or String.contains?(s, "/zero/") -> "cc0"
      nc?(s) and nd?(s) -> "cc-by-nc-nd"
      nc?(s) and sa?(s) -> "cc-by-nc-sa"
      nc?(s) -> "cc-by-nc"
      nd?(s) -> "cc-by-nd"
      sa?(s) -> "cc-by-sa"
      # A plain CC-BY (has "by", no restricting clause).
      String.contains?(s, "by") -> "cc-by"
      true -> "other"
    end
  end

  defp nc?(s), do: s =~ ~r/(^|[\s\-\/])nc([\s\-\/]|$)/
  defp nd?(s), do: s =~ ~r/(^|[\s\-\/])nd([\s\-\/]|$)/
  defp sa?(s), do: s =~ ~r/(^|[\s\-\/])sa([\s\-\/]|$)/

  @doc """
  True when a (canonical or raw) license permits displaying the verbatim full text in
  this commercial product — `cc0`, `cc-by`, `cc-by-sa` only. Everything else (NC, ND,
  `other`, `unknown`, `nil`) is false.

      iex> reusable?("cc-by")       #=> true
      iex> reusable?("CC BY-NC-ND") #=> false
      iex> reusable?(nil)           #=> false
  """
  def reusable?(license) when license in @reusable, do: true
  def reusable?(license) when license in @all, do: false
  def reusable?(nil), do: false
  def reusable?(raw) when is_binary(raw), do: reusable?(normalize(raw))
  def reusable?(_), do: false

  @doc "A human label for a canonical license, e.g. `\"CC BY\"`."
  def display_name("cc0"), do: "CC0 (public domain)"
  def display_name("cc-by"), do: "CC BY"
  def display_name("cc-by-sa"), do: "CC BY-SA"
  def display_name("cc-by-nc"), do: "CC BY-NC"
  def display_name("cc-by-nc-sa"), do: "CC BY-NC-SA"
  def display_name("cc-by-nd"), do: "CC BY-ND"
  def display_name("cc-by-nc-nd"), do: "CC BY-NC-ND"
  def display_name("other"), do: "Other license"
  def display_name(_), do: "License unknown"

  @doc """
  The canonical CC deed URL for a license (so the reader can link the notice). Returns
  a stored `license_url` verbatim if given one; otherwise derives the deed from the
  canonical value. `nil` for `other`/`unknown` with no stored URL.
  """
  def deed_url(_license, stored_url) when is_binary(stored_url) and stored_url != "", do: stored_url
  def deed_url(license, _stored_url), do: deed_url(license)

  def deed_url("cc0"), do: "https://creativecommons.org/publicdomain/zero/1.0/"
  def deed_url("cc-by"), do: "https://creativecommons.org/licenses/by/4.0/"
  def deed_url("cc-by-sa"), do: "https://creativecommons.org/licenses/by-sa/4.0/"
  def deed_url("cc-by-nc"), do: "https://creativecommons.org/licenses/by-nc/4.0/"
  def deed_url("cc-by-nc-sa"), do: "https://creativecommons.org/licenses/by-nc-sa/4.0/"
  def deed_url("cc-by-nd"), do: "https://creativecommons.org/licenses/by-nd/4.0/"
  def deed_url("cc-by-nc-nd"), do: "https://creativecommons.org/licenses/by-nc-nd/4.0/"
  def deed_url(_), do: nil
end
