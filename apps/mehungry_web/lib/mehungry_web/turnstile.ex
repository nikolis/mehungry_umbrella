defmodule MehungryWeb.Turnstile do
  @moduledoc """
  Server-side verification for Cloudflare Turnstile, the CAPTCHA on the
  registration form. Stops automated signups (e.g. Gmail-alias farming) at the
  source.

  Configured via `:turnstile_site_key` (public, embedded in the form) and
  `:turnstile_secret_key` (verification). When no secret key is configured
  (typical in dev/test), verification is skipped so local signups still work.
  """

  require Logger

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "The public site key for the widget, or nil when unconfigured."
  def site_key, do: normalize_key(Application.get_env(:mehungry, :turnstile_site_key))

  @doc "Whether Turnstile is enabled (a secret key is configured)."
  def enabled?, do: is_binary(secret_key()) and secret_key() != ""

  @doc """
  Verifies a Turnstile response token. Returns `:ok` when disabled or valid,
  `{:error, reason}` otherwise.
  """
  def verify(token, remote_ip \\ nil) do
    cond do
      not enabled?() ->
        :ok

      not (is_binary(token) and token != "") ->
        {:error, :missing_token}

      true ->
        do_verify(token, remote_ip)
    end
  end

  defp do_verify(token, remote_ip) do
    form =
      [secret: secret_key(), response: token]
      |> maybe_put_remote_ip(remote_ip)

    case HTTPoison.post(@verify_url, {:form, form}, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"success" => true}} -> :ok
          _ -> {:error, :verification_failed}
        end

      other ->
        Logger.warning("[Turnstile] verification request failed: #{inspect(other)}")
        {:error, :verification_unavailable}
    end
  end

  defp maybe_put_remote_ip(form, nil), do: form
  defp maybe_put_remote_ip(form, ip), do: form ++ [remoteip: ip]

  defp secret_key, do: normalize_key(Application.get_env(:mehungry, :turnstile_secret_key))

  # Env vars are easy to paste with stray surrounding whitespace, and a leading
  # space in the site key makes Cloudflare reject the widget outright ("Invalid
  # input for parameter sitekey"), breaking every signup. Trim so copy-paste
  # whitespace can't take down verification.
  defp normalize_key(value) when is_binary(value), do: String.trim(value)
  defp normalize_key(value), do: value
end
