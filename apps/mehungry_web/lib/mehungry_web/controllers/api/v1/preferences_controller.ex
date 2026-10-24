defmodule MehungryWeb.Api.V1.PreferencesController do
  @moduledoc """
  Onboarding & dietary preferences (spec §7): the static wizard vocabulary plus
  the current user's selections. Backed by `UserProfile.diet` /
  `lactose_intolerant` (via `Accounts.Profiles`).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts

  action_fallback MehungryWeb.Api.V1.FallbackController

  # Language labels are always shown in their own language, so they are not
  # translated. Diet/intolerance labels ARE localized to the request locale
  # (set on the process by `SetLocale`) — same gettext msgids as the web
  # onboarding wizard (`onboarding/form_component.ex`).
  @languages [%{code: "en", label: "EN — English"}, %{code: "el", label: "ΕΛ — Ελληνικά"}]

  @doc "GET /api/v1/preferences/options — static wizard vocabulary (localized)."
  def options(conn, _params) do
    json(
      conn,
      data(%{
        languages: @languages,
        diets: diets(),
        intolerances: intolerances()
      })
    )
  end

  defp diets do
    [
      %{key: "omnivore", label: gettext("Omnivore")},
      %{key: "vegetarian", label: gettext("Vegetarian")},
      %{key: "vegan", label: gettext("Vegan")},
      %{key: "pescatarian", label: gettext("Pescatarian")}
    ]
  end

  defp intolerances do
    [%{key: "lactose", label: gettext("I am lactose intolerant")}]
  end

  @doc "GET /api/v1/me/preferences — current selections + onboarding_level."
  def show(conn, _params) do
    profile = profile!(conn)
    json(conn, data(preferences_map(profile)))
  end

  @doc "PUT /api/v1/me/preferences — update diet/intolerances/language."
  def update(conn, params) do
    profile = profile!(conn)

    with {:ok, profile} <- Accounts.update_user_profile(profile, profile_attrs(params)) do
      json(conn, data(preferences_map(Accounts.get_user_profile_by_user_id(profile.user_id))))
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp profile!(conn), do: Accounts.get_user_profile_by_user_id(conn.assigns.current_user.id)

  defp preferences_map(profile) do
    %{
      language: profile.language_preference,
      diet: profile.diet,
      intolerances: if(profile.lactose_intolerant, do: ["lactose"], else: []),
      onboarding_level: profile.onboarding_level
    }
  end

  defp profile_attrs(params) do
    %{}
    |> put_if(params, "language", :language_preference)
    |> put_if(params, "diet", :diet)
    |> put_if(params, "onboarding_level", :onboarding_level)
    |> maybe_put_intolerances(params)
  end

  defp put_if(attrs, params, source_key, target_key) do
    case Map.fetch(params, source_key) do
      {:ok, value} -> Map.put(attrs, target_key, value)
      :error -> attrs
    end
  end

  defp maybe_put_intolerances(attrs, %{"intolerances" => list}) when is_list(list) do
    Map.put(attrs, :lactose_intolerant, "lactose" in list)
  end

  defp maybe_put_intolerances(attrs, _params), do: attrs
end
