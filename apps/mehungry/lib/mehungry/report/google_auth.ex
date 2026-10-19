defmodule Mehungry.Report.GoogleAuth do
  @moduledoc """
  Shared Google service-account auth for the read-only reporting pulls
  (`Mehungry.Report.GA4` and `Mehungry.Report.SearchConsole`). Both APIs are
  authorized by the **same** service account — the one JSON key in `GA4_SA_KEY`
  (named for GA4 for historical reasons; it also unlocks Search Console once the
  SA is granted access to that property).

  `credentials/0` parses the key (inline JSON or a path to the `.json` file);
  `access_token/2` mints a short-lived OAuth token for a given scope by signing
  the service-account JWT with Erlang's built-in `:public_key` (RS256) — no JWT
  dependency.
  """

  @token_uri "https://oauth2.googleapis.com/token"
  @timeout_ms 20_000

  @doc """
  Returns `{:ok, creds_map}` (with `"client_email"` + `"private_key"`),
  `{:skip, reason}` when `GA4_SA_KEY` is unset, or `{:error, reason}` when it is
  present but unparseable.
  """
  def credentials do
    case Application.get_env(:mehungry, :ga4_sa_key) do
      key when is_binary(key) and key != "" -> parse_sa_key(key)
      _ -> {:skip, "GA4_SA_KEY not set"}
    end
  end

  # Accept the JSON inline or a path to the .json file.
  defp parse_sa_key(key) do
    json =
      if String.starts_with?(String.trim_leading(key), "{"),
        do: {:ok, key},
        else: File.read(key)

    with {:ok, raw} <- json,
         {:ok, %{"client_email" => _, "private_key" => _} = creds} <- Jason.decode(raw) do
      {:ok, creds}
    else
      _ -> {:error, :invalid_service_account_key}
    end
  end

  @doc """
  Mints an access token for `scope` (a full scope URL) from the service account.
  Returns `{:ok, token}` or `{:error, reason}`.
  """
  def access_token(%{"client_email" => iss, "private_key" => pem} = creds, scope) do
    token_uri = Map.get(creds, "token_uri", @token_uri)
    now = System.system_time(:second)

    claims = %{
      "iss" => iss,
      "scope" => scope,
      "aud" => token_uri,
      "iat" => now,
      "exp" => now + 3600
    }

    with {:ok, assertion} <- sign_jwt(claims, pem) do
      form = [
        {"grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"},
        {"assertion", assertion}
      ]

      case HTTPoison.post(token_uri, {:form, form}, [], recv_timeout: @timeout_ms) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"access_token" => token}} -> {:ok, token}
            _ -> {:error, :unexpected_token_response}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          {:error, "token HTTP #{status}: #{String.slice(body, 0, 300)}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, {:transport_error, reason}}
      end
    end
  end

  def access_token(_, _), do: {:error, :invalid_service_account_key}

  # RS256-sign the JWT with :public_key (no JWT dependency).
  defp sign_jwt(claims, pem) do
    header = %{"alg" => "RS256", "typ" => "JWT"}
    signing_input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))

    case decode_pem(pem) do
      {:ok, key} ->
        signature = :public_key.sign(signing_input, :sha256, key)
        {:ok, signing_input <> "." <> b64(signature)}

      :error ->
        {:error, :invalid_private_key}
    end
  end

  defp decode_pem(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)
end
