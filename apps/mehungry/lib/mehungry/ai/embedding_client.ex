defmodule Mehungry.AI.EmbeddingClient do
  @moduledoc """
  Generates text embeddings using OpenAI's text-embedding-3-small model.

  Returns 1536-dimensional float vectors suitable for pgvector cosine similarity search.
  """

  require Logger

  @api_url "https://api.openai.com/v1/embeddings"
  @model "text-embedding-3-small"

  @doc """
  Generate an embedding for the given text.

  Returns `{:ok, [float]}` (1536 elements) or `{:error, reason}`.
  """
  def embed(text) when is_binary(text) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENAI_API_KEY not set"}
    else
      body = Jason.encode!(%{model: @model, input: text})

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case HTTPoison.post(@api_url, body, headers, recv_timeout: 30_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: raw}} ->
          case Jason.decode(raw) do
            {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
              {:ok, embedding}

            {:ok, other} ->
              Logger.error("EmbeddingClient: unexpected response shape: #{inspect(other)}")
              {:error, "unexpected response shape"}

            {:error, reason} ->
              {:error, "JSON decode failed: #{inspect(reason)}"}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: raw}} ->
          Logger.error("EmbeddingClient: HTTP #{status} — #{raw}")
          {:error, "HTTP #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("EmbeddingClient: request failed — #{inspect(reason)}")
          {:error, inspect(reason)}
      end
    end
  end
end
