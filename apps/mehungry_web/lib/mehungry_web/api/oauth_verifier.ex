defmodule MehungryWeb.Api.OAuthVerifier do
  @moduledoc """
  Server-side verification of the provider token a mobile client obtains from
  its native OAuth flow (spec §3). Exchanges the token for the authenticated
  user's profile, normalized to `%{name, email, profile_pic, provider}` — the
  shape `Mehungry.Accounts.OAuth.find_or_create_from_profile/1` expects.

  Supported providers: `"google"` (verifies an `id_token` via Google's
  tokeninfo endpoint) and `"facebook"` (reads `/me` with the `access_token`).

  Pluggable via the `:oauth_token_verifier` app config key so tests can stub the
  network call; the default implementation is this module's `verify/2`.
  """

  @behaviour MehungryWeb.Api.OAuthVerifier.Behaviour

  require Logger

  @google_tokeninfo "https://oauth2.googleapis.com/tokeninfo"
  @facebook_me "https://graph.facebook.com/me"

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

  def verify(_provider, _params), do: {:error, :unsupported_provider}
end

defmodule MehungryWeb.Api.OAuthVerifier.Behaviour do
  @moduledoc "Seam for stubbing provider-token verification in tests."
  @callback verify(provider :: String.t(), params :: map()) ::
              {:ok, map()} | {:error, atom()}
end
