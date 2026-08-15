defmodule Mehungry.AI.ImageGenerator do
  @moduledoc """
  Generates recipe cover images using the OpenAI gpt-image-1 API.

  Returns JPEG binary data ready to upload to S3.
  """

  require Logger

  @api_url "https://api.openai.com/v1/images/generations"
  @model "gpt-image-1"
  @size "1024x1024"
  @quality "medium"
  @timeout_ms 60_000

  @doc """
  Generates a food photo for the given recipe title and description.

  `cuisine` (optional) drives the visual styling — tableware, surface, background,
  and palette are derived from the cuisine so photos stop converging on the old
  hardcoded warm/rustic "amber" look. Pass `nil` when the cuisine is unknown.

  Returns `{:ok, jpeg_binary}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t(), String.t() | nil) ::
          {:ok, binary()} | {:error, term()}
  def generate(title, description, cuisine \\ nil) do
    api_key = Application.get_env(:mehungry, :openai_api_key, "")

    if api_key == "" do
      {:error, "OPENAI_API_KEY is not configured"}
    else
      prompt = build_prompt(title, description, cuisine)
      Logger.info("ImageGenerator: generating image for '#{title}'#{cuisine && " (#{cuisine})"}")
      request_image(api_key, prompt)
    end
  end

  # ── internals ─────────────────────────────────────────────────────────────────

  defp build_prompt(title, description, cuisine) do
    clean_desc =
      description
      |> String.replace(~r/#\S+/, "")
      |> String.trim()

    "Professional food photography of #{title}. #{clean_desc}. " <>
      cuisine_setting(cuisine) <>
      "Natural light, shallow depth of field, plated the way this dish is actually " <>
      "served. No text overlays, no watermarks, photorealistic."
  end

  # Derive the setting from the cuisine rather than hardcoding one look. The
  # explicit "do not default to warm amber tones" is what breaks the old
  # every-photo-looks-the-same problem.
  defp cuisine_setting(cuisine) when is_binary(cuisine) and cuisine != "" do
    "Styled authentically for #{cuisine} cuisine: use tableware, serving vessels, " <>
      "surface, and background that genuinely belong to #{cuisine} food culture, with " <>
      "a colour palette true to how this food really looks — do NOT default to warm " <>
      "amber/golden tones. "
  end

  defp cuisine_setting(_), do:
    "Plated simply and realistically on a surface that suits the dish; let the palette " <>
      "follow the food itself rather than defaulting to warm amber/golden tones. "

  defp request_image(api_key, prompt) do
    body =
      Jason.encode!(%{
        model: @model,
        prompt: prompt,
        n: 1,
        size: @size,
        quality: @quality
      })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]

    case HTTPoison.post(@api_url, body, headers, recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"data" => [%{"b64_json" => b64} | _]}} ->
            {:ok, Base.decode64!(b64)}

          {:ok, unexpected} ->
            Logger.warning("ImageGenerator: unexpected response: #{inspect(unexpected)}")
            {:error, "Unexpected OpenAI response format"}

          {:error, reason} ->
            {:error, "Failed to parse OpenAI response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.warning("ImageGenerator: OpenAI error #{code}: #{resp_body}")
        {:error, "OpenAI API returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("ImageGenerator: HTTP error: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
