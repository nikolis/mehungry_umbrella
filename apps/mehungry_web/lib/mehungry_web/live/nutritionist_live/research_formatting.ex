defmodule MehungryWeb.NutritionistLive.ResearchFormatting do
  @moduledoc """
  Shared render helpers for the nutritionist research surfaces — the per-condition
  results page (`ResearchCondition`) and the global search landing
  (`ResearchSearch`). Keeps the verification-label styling and the search-term
  highlighting identical across both.
  """
  use MehungryWeb, :html

  @doc "Human label for a fact's verification state (folds the `unverified_*` family)."
  def label_text("verified"), do: gettext("verified")
  def label_text("contradicted"), do: gettext("contradicted")
  def label_text(_unverified), do: gettext("unverified")

  @doc "Colour class for a verification label (basil / paprika / dim)."
  def label_class("verified"), do: "text-basil"
  def label_class("contradicted"), do: "text-paprika"
  def label_class(_unverified), do: "text-parchment-dim"

  @doc "A publication's PubMed URL (falls back to the PubMed home for a missing pmid)."
  def pubmed_url(%{pmid: pmid}) when is_binary(pmid) and pmid != "",
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  def pubmed_url(_), do: "https://pubmed.ncbi.nlm.nih.gov/"

  @doc "A compact authors byline (first one/two + et al.)."
  def authors_line(authors) when is_list(authors) and authors != [] do
    case authors do
      [a] -> a
      [a, b] -> "#{a}, #{b}"
      [a, b | _] -> "#{a}, #{b}, et al."
    end
  end

  def authors_line(_), do: nil

  @doc """
  Render `text` with the search query's terms wrapped in `<mark>`. With a blank
  query it renders the text verbatim, so it's safe to use on every title/finding
  unconditionally. Segment-based (not raw HTML) so interpolation stays escaped.
  """
  attr :text, :string, required: true
  attr :query, :any, default: nil

  def highlighted(assigns) do
    assigns = assign(assigns, :segments, highlight_segments(assigns.text, assigns.query))

    ~H"""
    <%= for {kind, seg} <- @segments do %><%= if kind == :hit do %><mark class="bg-basil/30 text-parchment rounded-sm px-0.5">{seg}</mark><% else %>{seg}<% end %><% end %>
    """
  end

  @doc """
  Split `text` into `[{:plain | :hit, substring}]` against the query's whitespace
  tokens (case-insensitive). Approximate vs the stemmed ts match, but good enough
  to show the nutritionist where their term landed.
  """
  def highlight_segments(text, query) when is_binary(text) do
    terms =
      (query || "")
      |> String.split(~r/\s+/u, trim: true)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case terms do
      [] ->
        [{:plain, text}]

      _ ->
        pattern = terms |> Enum.map(&Regex.escape/1) |> Enum.join("|")
        regex = Regex.compile!("(#{pattern})", "iu")

        regex
        |> Regex.split(text, include_captures: true, trim: false)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn piece ->
          if Regex.match?(regex, piece), do: {:hit, piece}, else: {:plain, piece}
        end)
    end
  end

  def highlight_segments(_text, _query), do: [{:plain, ""}]
end
