defmodule MehungryWeb.Api.Pagination do
  @moduledoc """
  Page-based pagination for the `/api/v1` surface (spec §1.3). MVP uses
  `?page=1&page_size=20`; `meta.has_more` drives infinite scroll on the client.
  """

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @doc """
  Parse `?page`/`?page_size` params into `{page, page_size}` (1-based), clamped.
  """
  def params(params) do
    {int(params["page"], @default_page) |> max(1),
     int(params["page_size"], @default_page_size) |> clamp(1, @max_page_size)}
  end

  @doc """
  Slice an in-memory list for `{page, page_size}` and return
  `{page_items, meta}` where meta carries `has_more`.
  """
  def paginate_list(list, {page, page_size}) when is_list(list) do
    offset = (page - 1) * page_size
    page_items = Enum.slice(list, offset, page_size)
    has_more = length(list) > offset + length(page_items)
    {page_items, meta(page, page_size, has_more)}
  end

  @doc "Build the `meta` map."
  def meta(page, page_size, has_more) do
    %{page: page, page_size: page_size, has_more: has_more}
  end

  defp int(nil, default), do: default

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp int(value, _default) when is_integer(value), do: value
  defp int(_, default), do: default

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)
end
