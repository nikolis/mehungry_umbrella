defmodule Mehungry.Settings do
  @moduledoc """
  Shared, DB-backed runtime settings — small values an admin can flip at runtime
  that must survive deploys and stay consistent across all running machines.

  `Application.put_env` can't do this: it's per-node (prod runs 2 machines, so a
  toggle would only affect the one that served the request) and resets on every
  restart/deploy. So these live in the `app_settings` table instead.

  Values are plain strings. The first consumer is the recipe-image provider
  toggle (`image_provider/0`), whose DB value **overrides** the
  `:recipe_image_provider` env default when set, so `RECIPE_IMAGE_PROVIDER`
  still works as the baseline when no admin override exists.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo
  alias Mehungry.Settings.AppSetting

  @image_provider_key "recipe_image_provider"
  @valid_image_providers [:openai, :flux]

  @doc "Returns the stored string value for `key`, or `default` if unset."
  @spec get(String.t(), term()) :: String.t() | term()
  def get(key, default \\ nil) do
    case Repo.get_by(AppSetting, key: key) do
      %AppSetting{value: value} when is_binary(value) -> value
      _ -> default
    end
  end

  @doc "Upserts `key` to `value` (stringified)."
  @spec put(String.t(), term()) :: {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t()}
  def put(key, value) do
    %AppSetting{}
    |> AppSetting.changeset(%{key: key, value: to_string(value)})
    |> Repo.insert(
      on_conflict: [
        set: [
          value: to_string(value),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        ]
      ],
      conflict_target: :key
    )
  end

  # ── recipe-image provider ────────────────────────────────────────────────────

  @doc """
  The active recipe-image provider as an atom (`:openai` | `:flux`).

  Precedence: admin DB override → `:recipe_image_provider` env default → `:openai`.
  """
  @spec image_provider() :: :openai | :flux
  def image_provider do
    case get(@image_provider_key) do
      "flux" -> :flux
      "openai" -> :openai
      _ -> Application.get_env(:mehungry, :recipe_image_provider, :openai)
    end
  end

  @doc """
  The provider that is **not** the active one (`:openai` ↔ `:flux`).

  Used by the owner per-recipe "regenerate image" action, which deliberately
  renders with the alternative backend rather than the configured default so a
  disappointing cover can be re-rolled on the other model.
  """
  @spec alternate_image_provider() :: :openai | :flux
  def alternate_image_provider do
    case image_provider() do
      :flux -> :openai
      _ -> :flux
    end
  end

  @doc "Persists the recipe-image provider override. Accepts `:openai`/`:flux` or their strings."
  @spec put_image_provider(atom() | String.t()) ::
          {:ok, AppSetting.t()} | {:error, Ecto.Changeset.t() | :invalid_provider}
  def put_image_provider(provider) do
    provider = if is_binary(provider), do: safe_atom(provider), else: provider

    if provider in @valid_image_providers do
      put(@image_provider_key, provider)
    else
      {:error, :invalid_provider}
    end
  end

  defp safe_atom("flux"), do: :flux
  defp safe_atom("openai"), do: :openai
  defp safe_atom(_), do: :invalid
end
