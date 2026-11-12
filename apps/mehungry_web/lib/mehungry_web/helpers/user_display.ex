defmodule MehungryWeb.UserDisplay do
  @moduledoc """
  Shared helpers for rendering a user as an "author card" (avatar + name that
  links to their profile).

  A user's `name` is optional at registration, so email signups (the majority)
  have a blank name. Rendering that bare name inside the link left the anchor
  empty and zero-height — nothing to click — which is why author cards in the
  feed and on the recipe-details page stopped being clickable. `display_name/1`
  guarantees a non-empty label so the link always has a hit target.

  `profile_path/1` always points at `/profile/:id`; public professionals are
  redirected to their `/nutritionists/:slug` page server-side (the
  `RedirectProProfile` plug + `ProfileLive.Index` `:show` action), so callers
  never need the `professional_profile` association preloaded.
  """

  @doc """
  A never-empty display label for a user: their `name`, else the local part of
  their email, else a generic fallback.
  """
  def display_name(user) do
    presence(Map.get(user, :name)) || email_handle(user) || "Community member"
  end

  @doc "Path to a user's public profile."
  def profile_path(%{id: id}), do: "/profile/#{id}"

  @doc "Single uppercase initial for an avatar fallback."
  def initial(user) do
    user |> display_name() |> String.first() |> Kernel.||("?") |> String.upcase()
  end

  defp email_handle(%{email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first() |> presence()
  end

  defp email_handle(_), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_), do: nil
end
