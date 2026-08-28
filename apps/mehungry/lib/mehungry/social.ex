defmodule Mehungry.Social do
  @moduledoc """
  Social publishing platform registry + global enablement flags.

  A platform can be disabled globally (e.g. while the platform app itself is
  broken / under review) via:

      config :mehungry, :social_platforms,
        facebook: true,
        instagram: false,
        pinterest: false

  A platform absent from the config defaults to **enabled**, so leaving the key
  unset preserves the previous "all platforms on" behaviour. Disabling a
  platform hides its user-facing share entry points and makes both the bot
  publisher and the user-flow components skip it — no posts are attempted.
  """

  @platforms ["facebook", "instagram", "pinterest"]

  @platform_atoms %{
    "facebook" => :facebook,
    "instagram" => :instagram,
    "pinterest" => :pinterest
  }

  @doc "All known social platforms, enabled or not."
  def all_platforms, do: @platforms

  @doc "The subset of `all_platforms/0` currently enabled by config."
  def enabled_platforms, do: Enum.filter(@platforms, &platform_enabled?/1)

  @doc """
  Whether `platform` (an atom or string like `"instagram"`) is enabled.
  Unknown platforms are treated as disabled; known platforms default to enabled
  when not present in `:social_platforms` config.
  """
  def platform_enabled?(platform) do
    case Map.get(@platform_atoms, to_string(platform)) do
      nil ->
        false

      key ->
        :mehungry
        |> Application.get_env(:social_platforms, [])
        |> Keyword.get(key, true)
    end
  end
end
