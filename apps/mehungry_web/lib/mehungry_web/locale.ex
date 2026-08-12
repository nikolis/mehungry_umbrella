defmodule MehungryWeb.Locale do
  @moduledoc """
  Single source of truth for the app's request/URL locale.

  Locale is carried as the leading URL path segment (`/en/…`, `/el/…`). This
  module owns the supported-locale list, detection priority, path rewriting for
  the language switcher, and the bridge from a URL locale to the legacy
  data-layer language name used by the `*_translation` tables.

  The supported list + default come from `config :mehungry_web, :locales`.
  """

  alias Mehungry.Accounts

  @doc "List of supported locale codes, e.g. `[\"en\", \"el\"]`."
  def supported do
    Application.get_env(:mehungry_web, :locales, [])
    |> Keyword.get(:supported, ["en"])
  end

  @doc "The default locale used for bare `/`, unknown locales, and fallbacks."
  def default do
    Application.get_env(:mehungry_web, :locales, [])
    |> Keyword.get(:default, "en")
  end

  @doc "Whether `locale` is one of the supported locales."
  def supported?(locale), do: locale in supported()

  @doc """
  Resolve the locale for a request using the Hierarchical Selection pattern,
  first non-nil wins: URL path param → session → user profile → `Accept-Language`
  → default.
  """
  def detect(%Plug.Conn{} = conn) do
    from_url = conn.path_params["locale"]
    from_session = Plug.Conn.get_session(conn, "locale")
    from_user = user_locale(conn)
    from_header = accept_language(conn)

    cond do
      supported?(from_url) -> from_url
      supported?(from_session) -> from_session
      supported?(from_user) -> from_user
      supported?(from_header) -> from_header
      true -> default()
    end
  end

  @doc """
  Rewrite `path` so its leading segment is `locale`. Inserts the prefix when the
  path has no locale segment yet, and preserves the query string. Used by the
  language switcher to point at the current page's twin in another language.
  """
  def swap_path(path, locale) when is_binary(path) do
    {path, query} =
      case String.split(path, "?", parts: 2) do
        [p, q] -> {p, "?" <> q}
        [p] -> {p, ""}
      end

    rest =
      case String.split(path, "/", trim: true) do
        [first | tail] -> if supported?(first), do: tail, else: [first | tail]
        [] -> []
      end

    "/" <> Enum.join([locale | rest], "/") <> query
  end

  @doc """
  Map a URL locale to the legacy language-row name used by the
  ingredient/category/measurement-unit translation tables (`languages.name`).
  """
  def data_language_name("el"), do: "Gr"
  def data_language_name("en"), do: "En"
  def data_language_name(_), do: "En"

  defp user_locale(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> Accounts.get_user_language(id)
      _ -> nil
    end
  end

  defp accept_language(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(fn part ->
      part
      |> String.split(";")
      |> List.first()
      |> String.trim()
      |> String.split("-")
      |> List.first()
      |> String.downcase()
    end)
    |> Enum.find(&supported?/1)
  end
end
