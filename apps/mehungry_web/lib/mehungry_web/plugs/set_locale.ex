defmodule MehungryWeb.Plugs.SetLocale do
  @moduledoc """
  Resolves the request locale from the `/:locale` URL segment and makes it
  authoritative for the request:

    * sets the Gettext process locale (so `gettext/1` renders in-language),
    * assigns `:locale`,
    * persists it to the session (so LiveView `on_mount` and later
      non-localized requests can recover it).

  Routes that carry no `:locale` segment (login, register, auth callbacks, …)
  still get a Gettext locale via `Locale.detect/1`, but are never redirected.
  A localized route hit with an *unsupported* locale segment (e.g. `/xx/browse`)
  is redirected to the same page under the detected/default locale.
  """
  import Plug.Conn

  alias MehungryWeb.Locale

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_params["locale"] do
      nil ->
        # Non-localized route: set the process locale but leave the URL alone.
        put_locale(conn, Locale.detect(conn))

      locale ->
        if Locale.supported?(locale) do
          put_locale(conn, locale)
        else
          conn
          |> Phoenix.Controller.redirect(to: replace_leading_locale(conn, Locale.detect(conn)))
          |> halt()
        end
    end
  end

  # The route matched `/:locale/…` with an unsupported locale, so the first path
  # segment is the (invalid) locale slot — drop it and prefix the detected one,
  # preserving the query string.
  defp replace_leading_locale(conn, locale) do
    rest = conn.request_path |> String.split("/", trim: true) |> tl()
    base = "/" <> Enum.join([locale | rest], "/")

    case conn.query_string do
      q when q in [nil, ""] -> base
      q -> base <> "?" <> q
    end
  end

  defp put_locale(conn, locale) do
    Gettext.put_locale(MehungryWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session("locale", locale)
  end
end
