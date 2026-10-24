defmodule MehungryWeb.Api.V1.SetLocale do
  @moduledoc """
  Resolves the request content locale (spec §Language) and installs it for the
  rest of the request:

    * sets the Gettext locale so server-rendered strings — onboarding vocabulary
      (`PreferencesController`) and error messages (`FallbackController`) — come
      back translated, and
    * stashes it in `conn.assigns.content_locale` so serializers/controllers can
      read the resolved locale without re-deriving it.

  Runs **after** the auth plug in each `/api/v1` pipeline so the authenticated
  user's `language_preference` is available as a resolution fallback. This is the
  API-side analogue of `MehungryWeb.Plugs.SetLocale` (which is URL-driven for the
  web).
  """
  @behaviour Plug

  alias MehungryWeb.Api.V1.Locale

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    locale = Locale.resolve(conn, conn.params)
    Gettext.put_locale(MehungryWeb.Gettext, locale)
    Plug.Conn.assign(conn, :content_locale, locale)
  end
end
