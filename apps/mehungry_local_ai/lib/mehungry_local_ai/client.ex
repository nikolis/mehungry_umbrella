defmodule MehungryLocalAi.Client do
  @moduledoc """
  HTTP client for the deployed app's local-AI REST API. Base URL + bearer token are
  read from app config (`:mehungry_local_ai, :server_base_url` / `:api_token`),
  overridable in `config/runtime.exs` from `LOCAL_AI_SERVER_URL` / `LOCAL_AI_API_TOKEN`.

  Three calls, mirroring the server routes:

    * `pending/2`        — `GET  /api/local_ai/pending`   → studies needing processing
    * `post_full_text/1` — `POST /api/local_ai/full_text` → store body + ledger attempt
    * `post_candidates/1`— `POST /api/local_ai/candidates`→ upsert measurement candidates
  """

  @timeout_ms 60_000

  @doc """
  Fetch up to `limit` studies (from `offset`) that still need PMC fetch + extraction.
  Returns `{:ok, %{studies: [%{study_id, pmid, compounds: [%{id, name, synonyms}]}], total: n}}`.
  """
  def pending(limit, offset \\ 0) do
    params = URI.encode_query(limit: limit, offset: offset)

    with {:ok, %{"studies" => studies, "total" => total}} <-
           request(:get, "/api/local_ai/pending?" <> params, nil) do
      {:ok, %{studies: Enum.map(studies, &normalize_study/1), total: total}}
    end
  end

  @doc "Post one PMC fetch result: `%{study_id, pmcid, source, body, outcome}`."
  def post_full_text(result) do
    request(:post, "/api/local_ai/full_text", result)
  end

  @doc "Post a batch of finding maps (each with `study_id`): `[%{study_id, compound_id, value, ...}]`."
  def post_candidates([]), do: {:ok, %{"written" => 0}}

  def post_candidates(candidates) when is_list(candidates) do
    request(:post, "/api/local_ai/candidates", %{candidates: candidates})
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp request(method, path, payload) do
    url = base_url() <> path
    body = if payload, do: Jason.encode!(payload), else: ""

    case HTTPoison.request(method, url, body, headers(), recv_timeout: @timeout_ms) do
      {:ok, %{status_code: code, body: resp}} when code in 200..299 ->
        decode(resp)

      {:ok, %{status_code: code, body: resp}} ->
        {:error, {:http, code, resp}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:network, reason}}
    end
  end

  defp decode(""), do: {:ok, %{}}

  defp decode(resp) do
    case Jason.decode(resp) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, {:bad_json, resp}}
    end
  end

  defp headers do
    [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"authorization", "Bearer " <> token()}
    ]
  end

  defp normalize_study(%{"study_id" => sid, "pmid" => pmid} = s) do
    compounds =
      (s["compounds"] || [])
      |> Enum.map(fn c ->
        %{id: c["id"], name: c["name"], synonyms: c["synonyms"] || []}
      end)

    %{study_id: sid, pmid: pmid, compounds: compounds}
  end

  defp base_url do
    Application.get_env(:mehungry_local_ai, :server_base_url, "http://localhost:4000")
    |> String.trim_trailing("/")
  end

  defp token, do: Application.get_env(:mehungry_local_ai, :api_token, "")
end
