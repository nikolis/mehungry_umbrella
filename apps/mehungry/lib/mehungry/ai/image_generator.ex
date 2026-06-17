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
  Returns `{:ok, jpeg_binary}` or `{:error, reason}`.
  """
  @spec generate(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def generate(title, description) do
    api_key = Application.get_env(:mehungry, :openai_api_key, "")

    if api_key == "" do
      {:error, "OPENAI_API_KEY is not configured"}
    else
      prompt = build_prompt(title, description)
      Logger.info("ImageGenerator: generating image for '#{title}'")
      request_image(api_key, prompt)
    end
  end

  # ── internals ─────────────────────────────────────────────────────────────────

  defp build_prompt(title, description) do
    clean_desc =
      description
      |> String.replace(~r/#\S+/, "")
      |> String.trim()

    "Professional food photography of #{title}. #{clean_desc}. " <>
      "Plated beautifully on a rustic wooden or marble surface, natural side lighting, " <>
      "shallow depth of field, garnished and styled. Warm appetizing tones. " <>
      "No text overlays, no watermarks, photorealistic."
  end

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
