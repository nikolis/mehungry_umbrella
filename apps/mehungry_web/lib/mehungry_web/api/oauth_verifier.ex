defmodule MehungryWeb.Api.OAuthVerifier do
  @moduledoc """
  Server-side verification of the provider token a mobile client obtains from
  its native OAuth flow (spec §3). Exchanges the token for the authenticated
  user's profile, normalized to `%{name, email, profile_pic, provider}` — the
  shape `Mehungry.Accounts.OAuth.find_or_create_from_profile/1` expects.

  Supported providers: `"google"` (verifies an `id_token` via Google's
  tokeninfo endpoint), `"facebook"` (reads `/me` with the `access_token`), and
  `"apple"` (verifies the Sign in with Apple identity-token JWT locally against
  Apple's published public keys — RS256, no Apple-side secret required).

  Pluggable via the `:oauth_token_verifier` app config key so tests can stub the
  network call; the default implementation is this module's `verify/2`.
  """

  @behaviour MehungryWeb.Api.OAuthVerifier.Behaviour

  require Logger

  @google_tokeninfo "https://oauth2.googleapis.com/tokeninfo"
  @facebook_me "https://graph.facebook.com/me"

  # Sign in with Apple. The native client (`expo-apple-authentication`) returns a
  # signed identity token (JWT) whose audience is the app's bundle id. We verify
  # the RS256 signature against Apple's JWKS and check iss/aud/exp — no client
  # secret or Service ID needed for the native-app flow.
  @apple_keys_url "https://appleid.apple.com/auth/keys"
  @apple_issuer "https://appleid.apple.com"
  @apple_audience "com.mehungry.ios"

  @doc """
  Dispatches to the configured implementation (this module by default).
  `params` is the request body (`%{"provider_token" => ..., ...}`).
  Returns `{:ok, profile_map}` or `{:error, reason}`.
  """
  def verify_provider(provider, params) do
    impl().verify(provider, params)
  end

  defp impl do
    Application.get_env(:mehungry_web, :oauth_token_verifier, __MODULE__)
  end

  @impl true
  def verify("google", %{"provider_token" => id_token}) when is_binary(id_token) do
    case HTTPoison.get(@google_tokeninfo <> "?id_token=" <> URI.encode(id_token)) do
      {:ok, %{status_code: 200, body: body}} ->
        claims = Jason.decode!(body)

        {:ok,
         %{
           name: claims["name"],
           email: claims["email"],
           profile_pic: claims["picture"],
           provider: "google"
         }}

      other ->
        Logger.warning("Google token verification failed: #{inspect(other)}")
        {:error, :invalid_provider_token}
    end
  end

  def verify("facebook", %{"provider_token" => access_token}) when is_binary(access_token) do
    query = URI.encode_query(%{"fields" => "id,name,email,picture", "access_token" => access_token})

    case HTTPoison.get(@facebook_me <> "?" <> query) do
      {:ok, %{status_code: 200, body: body}} ->
        info = Jason.decode!(body)

        {:ok,
         %{
           name: info["name"],
           email: info["email"] || "#{info["id"]}@facebook.user",
           profile_pic: get_in(info, ["picture", "data", "url"]),
           provider: "facebook"
         }}

      other ->
        Logger.warning("Facebook token verification failed: #{inspect(other)}")
        {:error, :invalid_provider_token}
    end
  end

  def verify("apple", %{"provider_token" => identity_token}) when is_binary(identity_token) do
    case verify_apple_identity_token(identity_token) do
      {:ok, claims} ->
        {:ok,
         %{
           # Apple's identity token carries no name (the full name is only sent
           # once, out-of-band, in the client response). Email may be the user's
           # address or a private-relay alias; both are deliverable. Fall back to
           # the stable `sub` if the user withheld email.
           name: nil,
           email: claims["email"] || "#{claims["sub"]}@appleid.user",
           profile_pic: nil,
           provider: "apple"
         }}

      {:error, reason} ->
        Logger.warning("Apple token verification failed: #{inspect(reason)}")
        {:error, :invalid_provider_token}
    end
  end

  def verify(_provider, _params), do: {:error, :unsupported_provider}

  # ── Sign in with Apple identity-token verification ───────────────────────

  # Verifies a Sign in with Apple identity token: RS256 signature against the
  # matching key in Apple's JWKS, then issuer / audience / expiry claims.
  defp verify_apple_identity_token(token) do
    with [header_b64, payload_b64, sig_b64] <- String.split(token, "."),
         {:ok, header} <- decode_jwt_segment(header_b64),
         {:ok, payload} <- decode_jwt_segment(payload_b64),
         {:ok, signature} <- Base.url_decode64(sig_b64, padding: false),
         {:ok, jwk} <- fetch_apple_jwk(header["kid"]),
         true <- valid_apple_signature?(header_b64 <> "." <> payload_b64, signature, jwk),
         :ok <- validate_apple_claims(payload) do
      {:ok, payload}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :bad_signature}
      _ -> {:error, :malformed_token}
    end
  end

  defp decode_jwt_segment(segment) do
    with {:ok, json} <- Base.url_decode64(segment, padding: false),
         {:ok, map} <- Jason.decode(json) do
      {:ok, map}
    else
      _ -> {:error, :malformed_token}
    end
  end

  defp fetch_apple_jwk(kid) when is_binary(kid) do
    case HTTPoison.get(@apple_keys_url) do
      {:ok, %{status_code: 200, body: body}} ->
        keys = Jason.decode!(body)["keys"] || []

        case Enum.find(keys, &(&1["kid"] == kid)) do
          nil -> {:error, :unknown_signing_key}
          jwk -> {:ok, jwk}
        end

      other ->
        Logger.warning("Apple JWKS fetch failed: #{inspect(other)}")
        {:error, :jwks_unavailable}
    end
  end

  defp fetch_apple_jwk(_), do: {:error, :malformed_token}

  # RS256 verification using the RSA modulus (`n`) and exponent (`e`) from the
  # JWK, via OTP's :public_key — no external JWT dependency.
  defp valid_apple_signature?(signing_input, signature, %{"n" => n_b64, "e" => e_b64}) do
    with {:ok, n} <- Base.url_decode64(n_b64, padding: false),
         {:ok, e} <- Base.url_decode64(e_b64, padding: false) do
      public_key =
        {:RSAPublicKey, :crypto.bytes_to_integer(n), :crypto.bytes_to_integer(e)}

      :public_key.verify(signing_input, :sha256, signature, public_key)
    else
      _ -> false
    end
  end

  defp valid_apple_signature?(_signing_input, _signature, _jwk), do: false

  defp validate_apple_claims(%{"iss" => iss, "aud" => aud, "exp" => exp})
       when is_integer(exp) do
    now = System.system_time(:second)

    cond do
      iss != @apple_issuer -> {:error, :bad_issuer}
      aud != @apple_audience -> {:error, :bad_audience}
      exp <= now -> {:error, :token_expired}
      true -> :ok
    end
  end

  defp validate_apple_claims(_), do: {:error, :missing_claims}
end

defmodule MehungryWeb.Api.OAuthVerifier.Behaviour do
  @moduledoc "Seam for stubbing provider-token verification in tests."
  @callback verify(provider :: String.t(), params :: map()) ::
              {:ok, map()} | {:error, atom()}
end
