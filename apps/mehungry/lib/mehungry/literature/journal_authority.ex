defmodule Mehungry.Literature.JournalAuthority do
  @moduledoc """
  The **journal-authority signal** for the nutritionist research search.

  Derived from the public-domain `ScientificStudy.citation_status` (the
  PubMed `MedlineCitation/@Status`): a `"MEDLINE"` status means the article was
  curated into MEDLINE, i.e. it appeared in a **MEDLINE-indexed** (vetted,
  selective) journal — a free, commercial-safe authority marker that needs no
  bundled dataset. Papers that are in PubMed but not MEDLINE-indexed
  (`"PubMed-not-MEDLINE"`, `"Publisher"`, …) carry no authority badge.

  Pure + extensible: a future DOAJ (vetted open-access) or SJR tier can be folded
  in here behind the same `label/1` / `rank/1` API without touching callers.
  Accepts either a `ScientificStudy` (or any map with `:citation_status`) or the
  raw status string.
  """

  alias Mehungry.Literature.ScientificStudy

  # MedlineCitation @Status values meaning "fully indexed in MEDLINE".
  @medline_statuses ~w(MEDLINE)

  @doc "True when the paper is in a MEDLINE-indexed journal."
  @spec medline_indexed?(ScientificStudy.t() | map() | String.t() | nil) :: boolean()
  def medline_indexed?(%{citation_status: status}), do: medline_indexed?(status)
  def medline_indexed?(status) when is_binary(status), do: status in @medline_statuses
  def medline_indexed?(_), do: false

  @doc "A short authority label for display, or `nil` when there is no signal."
  @spec label(ScientificStudy.t() | map() | String.t() | nil) :: String.t() | nil
  def label(study_or_status) do
    if medline_indexed?(study_or_status), do: "MEDLINE-indexed", else: nil
  end

  @doc """
  In-group sort rank (ascending): MEDLINE-indexed papers (0) come before the rest
  (1). A secondary signal under research-type grouping and recency.
  """
  @spec rank(ScientificStudy.t() | map() | String.t() | nil) :: 0 | 1
  def rank(study_or_status), do: if(medline_indexed?(study_or_status), do: 0, else: 1)
end
