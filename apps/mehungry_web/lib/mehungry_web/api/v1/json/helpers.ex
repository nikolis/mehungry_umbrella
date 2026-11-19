defmodule MehungryWeb.Api.V1.JSON.Helpers do
  @moduledoc """
  Shared helpers for building the `/api/v1` response envelope (spec §1.1).

      Success (single): %{data: ...}
      Success (list):   %{data: [...], meta: %{page:, page_size:, has_more:}}
      Error:            %{errors: %{detail:, fields:}}

  JSON view modules (`*JSON`) return plain maps that get passed to
  `Phoenix.Controller.json/2`; Ecto structs are never encoded directly.
  """

  @doc "Wrap a single resource."
  def data(payload), do: %{data: payload}

  @doc "Wrap a list resource with pagination/meta."
  def data(payload, meta) when is_map(meta), do: %{data: payload, meta: meta}

  @doc "Build an error envelope."
  def errors(detail) when is_binary(detail), do: %{errors: %{detail: detail}}

  def errors(detail, fields) when is_binary(detail) and is_map(fields) do
    %{errors: %{detail: detail, fields: fields}}
  end

  @doc """
  Serialize a naive datetime without a zone (spec §1 — `start_dt`/`end_dt` on
  meals/baskets are stored naive and emitted as `2026-08-10T14:30:00`).
  """
  def naive(nil), do: nil
  def naive(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)

  @doc "Serialize a UTC timestamp as an ISO-8601 Z string."
  def utc(nil), do: nil
  def utc(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  def utc(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @doc """
  Localize a stored `name => node` nutrient map for `locale` — the one place the
  REST nutrient surfaces (recipe detail, daily meal nutrition) share. Resolves
  fatty-acid leaves to their common names (same as the web accordion) and then
  translates the display names via `MehungryWeb.NutrientLabels`. No-op for the
  source locale; `nil`/empty in → `%{}`.

  Every node (at every depth, in every locale) also gets a `canonical_name`: its
  English display name, captured **before** translation. `name` and the map keys
  are localized display text, so clients must identify a nutrient ("is this the
  fat total?") by `canonical_name` — matching on `name` silently breaks outside
  English.
  """
  def localize_nutrients(nil, _locale), do: %{}

  def localize_nutrients(map, locale) when is_map(map) do
    map
    |> Map.new(fn {name, node} ->
      node =
        node
        |> Mehungry.Food.Nutrition.FattyAcidMatcher.resolve_names()
        |> put_canonical_names(name)

      {name, node}
    end)
    |> MehungryWeb.NutrientLabels.translate_tree(locale)
  end

  # Stamp `canonical_name` on a node and its `children`, recursively. `fallback`
  # is the map key, used for a top-level node that carries no `name` of its own.
  defp put_canonical_names(node, fallback \\ nil)

  defp put_canonical_names(node, fallback) when is_map(node) and not is_struct(node) do
    node =
      case node_get(node, "name") || fallback do
        name when is_binary(name) -> node_put(node, "canonical_name", name)
        _ -> node
      end

    case node_get(node, "children") do
      children when is_list(children) and children != [] ->
        node_put(node, "children", Enum.map(children, &put_canonical_names/1))

      _ ->
        node
    end
  end

  defp put_canonical_names(other, _fallback), do: other

  # Read/write a node key tolerant of string- or atom-keyed maps, writing in
  # whichever representation the node already uses.
  defp node_get(node, key), do: Map.get(node, key) || Map.get(node, String.to_atom(key))

  defp node_put(node, key, value) do
    if Enum.any?(Map.keys(node), &is_atom/1),
      do: Map.put(node, String.to_atom(key), value),
      else: Map.put(node, key, value)
  end
end
