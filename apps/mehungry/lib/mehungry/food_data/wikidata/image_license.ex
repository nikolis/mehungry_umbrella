defmodule Mehungry.FoodData.Wikidata.ImageLicense do
  @moduledoc """
  The legal gate for re-hosting a Wikimedia Commons image on a `/foods` page.

  "It's on Wikipedia" is **not** a licence — every Commons file carries its own, and
  some are non-free / fair-use and may not be reused. `reusable?/1` decides, from the
  licence metadata the `FoodData.Wikidata.Client` reads out of the Commons `imageinfo`
  `extmetadata`, whether we are allowed to display + re-host the image.

  Policy (fail **closed** — an unrecognized licence is rejected):

    * **Allow**  — CC0, public domain / PD mark, CC BY (any version), CC BY-SA (any
      version). These permit commercial reuse with attribution, which we always give.
    * **Reject** — NonCommercial (`nc`), NoDerivs (`nd`), fair-use / non-free, anything
      carrying a non-empty `Restrictions` note (trademark / personality rights), or any
      code we don't explicitly recognize.

  Even for CC0 / public-domain images — where credit isn't strictly required — we still
  record and show attribution (`attribution_text/1`): "if we're allowed to display it,
  we credit it".
  """

  @reject_tokens ~w(nc nd)

  @doc """
  True if the image (the `:image` map from `FoodData.Wikidata.Client`) may be reused.
  Decides on the machine `:license_code`, falling back to the display `:license_name`.
  """
  def reusable?(image) when is_map(image) do
    restrictions = image[:restrictions]
    code = normalize(image[:license_code] || image[:license_name])

    cond do
      is_binary(restrictions) and String.trim(restrictions) != "" -> false
      is_nil(code) -> false
      true -> allowed_code?(code)
    end
  end

  def reusable?(_), do: false

  @doc """
  A human-readable credit line for the image — "<artist>, <licence>, via Wikimedia
  Commons" (omitting any missing part). Used for the API field and image `alt`/`title`;
  the HTML surfaces link the licence + source separately.
  """
  def attribution_text(image) when is_map(image) do
    [image[:artist], image[:license_name], "via Wikimedia Commons"]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end

  def attribution_text(_), do: "via Wikimedia Commons"

  # ── internal ──────────────────────────────────────────────────────────────────

  defp normalize(nil), do: nil
  defp normalize(code) when is_binary(code), do: code |> String.downcase() |> String.trim()

  defp allowed_code?(code) do
    tokens = String.split(code, ~r/[^a-z0-9.]+/, trim: true)

    cond do
      Enum.any?(@reject_tokens, &(&1 in tokens)) -> false
      String.contains?(code, "fair") -> false
      String.contains?(code, "nonfree") or String.contains?(code, "non-free") -> false
      public_domain?(code, tokens) -> true
      cc_by?(tokens) -> true
      true -> false
    end
  end

  defp public_domain?(code, tokens) do
    "cc0" in tokens or "pd" in tokens or "pdm" in tokens or
      String.contains?(code, "public domain") or String.contains?(code, "publicdomain")
  end

  defp cc_by?(tokens), do: "cc" in tokens and "by" in tokens
end
