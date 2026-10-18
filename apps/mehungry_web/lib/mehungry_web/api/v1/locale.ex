defmodule MehungryWeb.Api.V1.Locale do
  @moduledoc """
  Resolves the content locale for an `/api/v1` request (spec §Language).

  Precedence: explicit `?lang=en|el` → `Accept-Language` header → the
  authenticated user's `language_preference` → `"en"`. Only the supported content
  locales are honored; anything else falls through. This is the API-side analogue
  of `MehungryWeb.Locale.detect/1` (which is URL-driven for the web).
  """

  alias Mehungry.Accounts

  @supported ~w(en el)

  @doc "Resolve the request locale. `params` is the controller's action params."
  def resolve(conn, params \\ %{}) do
    param_lang(params) || header_lang(conn) || profile_lang(conn) || "en"
  end

  defp param_lang(params) when is_map(params), do: validate(Map.get(params, "lang"))
  defp param_lang(_), do: nil

  defp header_lang(conn) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
      [value | _] ->
        value
        |> String.split(",")
        |> List.first()
        |> String.split("-")
        |> List.first()
        |> String.trim()
        |> String.downcase()
        |> validate()

      _ ->
        nil
    end
  end

  defp profile_lang(conn) do
    case conn.assigns[:current_user] do
      nil -> nil
      user -> validate(Accounts.get_user_language(user.id))
    end
  end

  defp validate(lang) when lang in @supported, do: lang
  defp validate(_), do: nil
end
