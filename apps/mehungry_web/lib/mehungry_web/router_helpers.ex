defmodule MehungryWeb.RouterHelpers do
  @moduledoc """
  Router macros shared by `MehungryWeb.Router`.
  """

  @doc """
  Emit a `live` route at both its bare path and the locale-prefixed `/:locale`
  variant, so locale-aware URLs (`/el/browse`) and legacy/unprefixed URLs
  (`/browse`) both resolve to the same LiveView.

  This keeps every `~p` verified-route literal compiling while links migrate to
  the locale-prefixed form, and lets the head partial's `rel=canonical` point
  crawlers at the prefixed URL so the duplicate paths aren't an SEO problem. Must
  be used inside a router scope where `Phoenix.LiveView.Router.live/3` is imported.
  """
  defmacro localized_live(path, module, action) do
    prefixed = "/:locale" <> path

    quote do
      live(unquote(path), unquote(module), unquote(action))
      live(unquote(prefixed), unquote(module), unquote(action))
    end
  end
end
