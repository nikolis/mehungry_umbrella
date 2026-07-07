defmodule Mehungry.AI.Client do
  @moduledoc """
  Shared HTTP client for the Anthropic Messages API.

  Handles authentication, request construction, response parsing, and
  retry on rate-limit (529) and transient timeout errors with exponential
  backoff. All AI modules in this application should use this instead of
  raw HTTPoison calls.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-4-5-20251001"
  @default_max_tokens 2048
  @timeout_ms 90_000
  @max_retries 3
  @retry_base_ms 1_000

  @type message :: %{role: String.t(), content: String.t() | list(map())}

  @type params :: %{
          required(:system) => String.t(),
          required(:messages) => [message()],
          optional(:model) => String.t(),
          optional(:max_tokens) => pos_integer(),
          optional(:tools) => [map()]
        }

  @type response :: %{
          content: [map()],
          stop_reason: String.t(),
          usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
        }

  @doc """
  Makes a request to the Anthropic Messages API.

  Required keys in `params`:
    - `:system`   — system prompt string
    - `:messages` — list of `%{role: "user"|"assistant", content: ...}` maps

  Optional keys:
    - `:model`      — defaults to #{@default_model}
    - `:max_tokens` — defaults to #{@default_max_tokens}
    - `:tools`      — list of tool-definition maps (enables tool-use mode)

  Returns `{:ok, response}` or `{:error, reason}`.
  """
  @spec request(params()) :: {:ok, response()} | {:error, term()}
  def request(params) do
    case Application.get_env(:mehungry, :anthropic_api_key, "") do
      "" -> {:error, "ANTHROPIC_API_KEY is not configured"}
      api_key -> do_request(api_key, params, 0)
    end
  end

  @doc """
  Convenience helper: extracts the plain text from a response's content blocks.
  Returns an empty string if there are no text blocks.
  """
  @spec text_from(%{content: [map()]}) :: String.t()
  def text_from(%{content: blocks}) do
    blocks
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("\n", & &1["text"])
  end

  # ── internals ────────────────────────────────────────────────────────────────

  defp do_request(_key, _params, @max_retries) do
    {:error, "Request failed after #{@max_retries} retries"}
  end

  defp do_request(api_key, params, attempt) do
    case HTTPoison.post(@api_url, build_body(params), headers(api_key), recv_timeout: @timeout_ms) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %HTTPoison.Response{status_code: 529}} ->
        delay = round(@retry_base_ms * :math.pow(2, attempt))
        Logger.warning("AI.Client: rate limited, retrying in #{delay}ms (attempt #{attempt + 1})")
        Process.sleep(delay)
        do_request(api_key, params, attempt + 1)

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.warning("AI.Client: API error #{code}: #{body}")
        {:error, "API returned status #{code}"}

      {:error, %HTTPoison.Error{reason: :timeout}} when attempt < @max_retries - 1 ->
        Logger.warning("AI.Client: timeout, retrying (attempt #{attempt + 1})")
        do_request(api_key, params, attempt + 1)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("AI.Client: HTTP error: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp build_body(params) do
    base = %{
      model: Map.get(params, :model, @default_model),
      max_tokens: Map.get(params, :max_tokens, @default_max_tokens),
      system: params.system,
      messages: params.messages
    }

    base =
      case Map.get(params, :tools) do
        tools when tools not in [nil, []] -> Map.put(base, :tools, tools)
        _ -> base
      end

    Jason.encode!(base)
  end

  defp headers(api_key) do
    [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"content" => content, "stop_reason" => stop_reason} = resp} ->
        usage = Map.get(resp, "usage", %{})

        {:ok,
         %{
           content: content,
           stop_reason: stop_reason,
           usage: %{
             input_tokens: Map.get(usage, "input_tokens", 0),
             output_tokens: Map.get(usage, "output_tokens", 0)
           }
         }}

      {:ok, unexpected} ->
        Logger.warning("AI.Client: unexpected response shape: #{inspect(unexpected)}")
        {:error, "Unexpected API response format"}

      {:error, reason} ->
        Logger.warning("AI.Client: JSON parse error: #{inspect(reason)}")
        {:error, "Failed to parse API response"}
    end
  end
end
