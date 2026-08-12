defmodule MehungryWeb.RestoreLocale do
  @moduledoc """
  `on_mount` hook that makes the URL locale authoritative inside LiveViews.

  The connected LiveView process does not run the router pipeline, so the
  `SetLocale` plug's `Gettext.put_locale` doesn't carry over — this hook
  re-establishes it from the `:locale` path param (falling back to the session),
  and assigns both `:locale` and `:current_language` (the latter is what the
  existing content-localization consumers read). It is listed *before* the
  auth `on_mount` hooks so their `assign_new(:current_language, …)` becomes a
  no-op and the URL wins.
  """
  import Phoenix.Component, only: [assign: 3]

  alias MehungryWeb.Locale

  def on_mount(_name, params, session, socket) do
    locale =
      cond do
        is_map(params) and Locale.supported?(params["locale"]) -> params["locale"]
        Locale.supported?(session["locale"]) -> session["locale"]
        true -> Locale.default()
      end

    Gettext.put_locale(MehungryWeb.Gettext, locale)

    {:cont,
     socket
     |> assign(:locale, locale)
     |> assign(:current_language, locale)}
  end
end
