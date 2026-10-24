defmodule Mehungry.AI.FluxImageGenerator do
  @moduledoc """
  Generates recipe cover images using Black Forest Labs' **FLUX 2 [pro]** API.

  Unlike the synchronous OpenAI image API, FLUX is **async**: you POST a
  generation request, get back a `polling_url`, then poll until the status is
  `"Ready"`. The result is a signed image URL that **expires ~10 minutes** after
  generation, so we download the bytes immediately and return them — the caller
  (`Mehungry.RecipeImageWorker`) re-hosts them in object storage.

  Takes an already-built prompt (the prompt engineering is shared with the
  OpenAI provider in `Mehungry.AI.ImageGenerator`) and returns `{:ok, jpeg_binary}`
  or `{:error, reason}`, matching the OpenAI provider's contract so the two are
  drop-in interchangeable behind `ImageGenerator.generate/3`.
  """

  require Logger

  # Stable FLUX 2 pro generation endpoint (not the `-preview` variant). Global
  # host; EU/US regional hosts exist but the polling_url the submit returns is
  # already absolute, so we only need the host for the submit call.
  @submit_url "https://api.bfl.ai/v1/flux-2-pro"

  # Landscape 3:2 to match the app's aspect-video covers (same framing as the
  # OpenAI provider's 1536x1024). ~1.57 MP.
  @width 1536
  @height 1024
  @output_format "jpeg"

  @poll_interval_ms 1_500
  @max_poll_ms 90_000
  @http_timeout_ms 30_000
  @download_timeout_ms 60_000

  # In-progress statuses we keep polling through; everything else that isn't
  # "Ready" is treated as a terminal failure.
  @pending_statuses ~w(Pending Reasoning Generating)

  @doc """
  Generates an image for the given prompt. The second arg is accepted for
  signature parity with the OpenAI provider; FLUX 2 pro has no per-request
  quality tier, so quality opts are ignored.
  """
  @spec generate(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(prompt, _opts \\ []) do
    api_key = Application.get_env(:mehungry, :bfl_api_key, "")

    if api_key == "" do
      {:error, "BFL_API_KEY is not configured"}
    else
      with {:ok, polling_url} <- submit(api_key, prompt),
           {:ok, image_url} <- poll(api_key, polling_url, @max_poll_ms),
           {:ok, binary} <- download(image_url) do
        {:ok, binary}
      end
    end
  end

  # ── internals ─────────────────────────────────────────────────────────────────

  defp submit(api_key, prompt) do
    body =
      Jason.encode!(%{
        prompt: prompt,
        width: @width,
        height: @height,
        output_format: @output_format
      })

    case HTTPoison.post(@submit_url, body, headers(api_key), recv_timeout: @http_timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"polling_url" => polling_url}} when is_binary(polling_url) ->
            {:ok, polling_url}

          {:ok, unexpected} ->
            Logger.warning("FluxImageGenerator: unexpected submit response: #{inspect(unexpected)}")
            {:error, "Flux submit: unexpected response format"}

          {:error, reason} ->
            {:error, "Flux submit: failed to parse response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.warning("FluxImageGenerator: submit error #{code}: #{resp_body}")
        {:error, "Flux submit returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Flux submit HTTP error: #{inspect(reason)}"}
    end
  end

  defp poll(_api_key, _polling_url, remaining_ms) when remaining_ms <= 0 do
    {:error, "Flux generation timed out after #{@max_poll_ms}ms"}
  end

  defp poll(api_key, polling_url, remaining_ms) do
    case HTTPoison.get(polling_url, headers(api_key), recv_timeout: @http_timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"status" => "Ready", "result" => %{"sample" => sample}}}
          when is_binary(sample) ->
            {:ok, sample}

          {:ok, %{"status" => status}} when status in @pending_statuses ->
            Process.sleep(@poll_interval_ms)
            poll(api_key, polling_url, remaining_ms - @poll_interval_ms)

          {:ok, %{"status" => status}} ->
            Logger.warning("FluxImageGenerator: terminal status #{status}: #{resp_body}")
            {:error, "Flux generation failed: #{status}"}

          {:ok, unexpected} ->
            {:error, "Flux poll: unexpected response #{inspect(unexpected)}"}

          {:error, reason} ->
            {:error, "Flux poll: failed to parse response: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        Logger.warning("FluxImageGenerator: poll error #{code}: #{resp_body}")
        {:error, "Flux poll returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Flux poll HTTP error: #{inspect(reason)}"}
    end
  end

  # The FLUX result URL expires ~10 min after generation, so download now.
  defp download(image_url) do
    case HTTPoison.get(image_url, [], recv_timeout: @download_timeout_ms, follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: binary}} ->
        {:ok, binary}

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "Flux image download returned status #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Flux image download HTTP error: #{inspect(reason)}"}
    end
  end

  defp headers(api_key) do
    [
      {"Content-Type", "application/json"},
      {"accept", "application/json"},
      {"x-key", api_key}
    ]
  end
end
