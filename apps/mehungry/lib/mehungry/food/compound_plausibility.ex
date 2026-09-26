defmodule Mehungry.Food.CompoundPlausibility do
  @moduledoc """
  The LLM "reality check" that gates auto-promotion of a `(species, compound)`
  candidate into a curated `contains` fact.

  Document-level literature co-occurrence (the candidate's evidence) cannot tell a
  genuine constituent apart from an extraction solvent (Ethanol), a scavenged target
  (reactive oxygen species), a contaminant (heavy metals), or an assay reagent. This
  module asks a cheap model that single question — is `compound` plausibly an
  *intrinsic natural dietary constituent* of `species`? — feeding it the titles /
  abstracts of the very studies the candidate was scored from.

  One JSON prompt via `AI.Client.request/1`, fence-strip + `Jason.decode`, mirroring
  `Mehungry.AI.TaxonomyClassifier`. Behind the `:compound_plausibility_judge` config
  seam so tests stub it. See `docs/science/compound_candidates.md`.
  """

  @behaviour Mehungry.Food.CompoundPlausibilityBehaviour

  require Logger

  # Cheap + fast: this is a single yes/no/uncertain judgement per new candidate.
  @model "claude-haiku-4-5-20251001"
  # Cap how much study text we send — a handful of titles/abstracts is plenty of context.
  @max_studies 6
  @abstract_chars 600

  @impl Mehungry.Food.CompoundPlausibilityBehaviour
  def judge(species, compound, studies) do
    case call_api(system_prompt(), user_prompt(species, compound, studies)) do
      {:ok, text} -> parse(text)
      error -> error
    end
  end

  defp system_prompt do
    """
    You are a food scientist vetting AUTOMATED claims that a food naturally contains a
    chemical compound. The claims were generated purely from co-occurrence — a chemical
    was mentioned in a research paper about the food — so many are false positives.

    A claim is IMPLAUSIBLE when the compound is not an intrinsic natural dietary
    constituent of the food, but instead appears because it is:
      - a laboratory SOLVENT or reagent used to process/extract the food
        (e.g. ethanol, methanol, acetone, DPPH);
      - a CONTAMINANT that depends on growing/processing conditions
        (e.g. heavy metals, pesticides);
      - a non-specific CLASS or measured TARGET rather than a discrete compound
        (e.g. "reactive oxygen species", "free radicals", "heavy metals");
      - a metabolic by-product being MEASURED or studied, not something in the food.

    A claim is PLAUSIBLE when the compound is a real phytochemical / nutrient / bioactive
    that the food genuinely contains (e.g. an apricot containing beta-carotene, spinach
    containing oxalate).

    Use "uncertain" only when the evidence truly does not let you decide.

    Return ONLY a JSON object, no markdown, no extra keys:
    {"verdict": "plausible" | "implausible" | "uncertain", "reason": "<one short sentence>"}
    """
  end

  defp user_prompt(species, compound, studies) do
    """
    Food species: #{species_label(species)}
    Claimed compound: #{compound_label(compound)}

    Co-occurring study evidence (titles/abstracts the claim was derived from):
    #{studies_block(studies)}

    Is it plausible that this food naturally CONTAINS this compound as an intrinsic
    dietary constituent? Respond with the JSON object.
    """
  end

  defp species_label(species) do
    sci = Map.get(species, :scientific_name)
    base = Map.get(species, :name) || "unknown"
    if sci in [nil, ""], do: base, else: "#{base} (#{sci})"
  end

  defp compound_label(compound) do
    syn =
      case Map.get(compound, :synonyms) do
        list when is_list(list) and list != [] -> " — also: #{Enum.join(Enum.take(list, 5), ", ")}"
        _ -> ""
      end

    type = Map.get(compound, :compound_type)
    type_str = if type in [nil, ""], do: "", else: " [type: #{type}]"
    "#{Map.get(compound, :name)}#{type_str}#{syn}"
  end

  defp studies_block([]), do: "(no study text available)"

  defp studies_block(studies) do
    studies
    |> Enum.take(@max_studies)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {study, i} ->
      title = Map.get(study, :title) || "(untitled)"
      abstract = (Map.get(study, :abstract) || "") |> String.slice(0, @abstract_chars)
      "#{i}. #{title}\n   #{abstract}"
    end)
  end

  defp parse(text) do
    cleaned =
      text
      |> String.trim()
      |> String.replace(~r/```json\s*/i, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    with {:ok, %{"verdict" => verdict} = map} <- Jason.decode(cleaned),
         v when v in [:plausible, :implausible, :uncertain] <- normalize_verdict(verdict) do
      {:ok, %{verdict: v, reason: reason(map)}}
    else
      _ ->
        Logger.warning("CompoundPlausibility: failed to parse response: #{inspect(text)}")
        {:error, :unparseable}
    end
  end

  defp normalize_verdict(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      "plausible" -> :plausible
      "implausible" -> :implausible
      "uncertain" -> :uncertain
      _ -> :invalid
    end
  end

  defp normalize_verdict(_), do: :invalid

  defp reason(%{"reason" => r}) when is_binary(r), do: String.slice(r, 0, 500)
  defp reason(_), do: ""

  defp call_api(system, user) do
    case client().request(%{
           model: @model,
           system: system,
           messages: [%{role: "user", content: user}],
           max_tokens: 512
         }) do
      {:ok, response} -> {:ok, Mehungry.AI.Client.text_from(response)}
      error -> error
    end
  end

  # The Anthropic client, swappable in tests via `:ai_client` (mirrors `AI.Agent`).
  defp client, do: Application.get_env(:mehungry, :ai_client, Mehungry.AI.Client)
end
