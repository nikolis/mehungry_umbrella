defmodule MehungrySeasonality.Mappings do
  @moduledoc """
  The species ↔ external-product crosswalk: which agri-food portal product and which
  Comext HS/CN code(s) stand for a food species. Curated by an admin; a species with
  no mapping is simply not fetched.
  """

  import Ecto.Query, warn: false

  alias MehungrySeasonality.Agridata
  alias MehungrySeasonality.{Core, Mapping}

  # Jaro score at or above which a product name is offered as a suggestion.
  @suggest_threshold 0.88

  @doc "All mappings."
  def list do
    Core.repo().all(from(m in Mapping, order_by: [asc: m.source, asc: m.external_code]))
  end

  @doc "Mappings of one species."
  def for_species(species_id) do
    Core.repo().all(
      from(m in Mapping,
        where: m.foundemental_species_id == ^species_id,
        order_by: [asc: m.source, asc: m.external_code]
      )
    )
  end

  @doc "Ids of every species that has at least one mapping."
  def mapped_species_ids do
    Core.repo().all(from(m in Mapping, distinct: true, select: m.foundemental_species_id))
  end

  @doc "Add a mapping. `attrs`: `foundemental_species_id`, `source`, `external_code`, `label`."
  def save(attrs) do
    %Mapping{} |> Mapping.changeset(attrs) |> Core.repo().insert()
  end

  @doc "Remove a mapping by id. Already-fetched observations are kept until the next fetch."
  def delete(id) do
    case Core.repo().get(Mapping, id) do
      nil -> {:error, :not_found}
      mapping -> Core.repo().delete(mapping)
    end
  end

  @doc """
  Suggest an agri-food portal product for every species that has no `agridata`
  mapping yet, by fuzzy-matching the species name against the portal's product list.
  Read-only. Returns `{:ok, %{species_id => %{product, score}}}` or `{:error, reason}`
  when the product list cannot be fetched.
  """
  def suggest_agridata do
    with {:ok, products} <- Agridata.Client.impl().products() do
      candidates = Enum.reject(products, &derived_product?/1)

      already =
        Core.repo().all(
          from(m in Mapping, where: m.source == "agridata", select: m.foundemental_species_id)
        )
        |> MapSet.new()

      suggestions =
        Core.list_species()
        |> Enum.reject(&MapSet.member?(already, &1.id))
        |> Enum.flat_map(fn species ->
          case best_match(species.name, candidates) do
            nil -> []
            match -> [{species.id, match}]
          end
        end)
        |> Map.new()

      {:ok, suggestions}
    end
  end

  @doc """
  The agri-food portal products that carry a **local signal** for a country — at least
  one producer-side price quote last year — whether or not a species is mapped to
  them yet. This is the catalogue of what seasonality *could* show for the country.

      {:ok, [%{product: "Peaches", months_quoted: 6, suggested_species_id: 12 | nil}]}

  `suggested_species_id` is the best fuzzy name match among existing species (a hint).
  One API call for the product list and one for the country's quotes; `{:error, _}`
  when the portal is unreachable. `opts[:year]` overrides the year looked at.
  """
  def available_products(country, opts \\ []) do
    year = Keyword.get(opts, :year, Date.utc_today().year - 1)
    client = Agridata.Client.impl()

    with {:ok, names} <- client.products(),
         {:ok, rows} <- client.quotes(country, [year], nil) do
      species = Core.list_species()

      products =
        rows
        # Attribute against every name first, so a "… for processing" row is not
        # counted under its base product, then drop the derived products.
        |> Agridata.Parser.months_by_product(names)
        |> Enum.reject(fn {product, _months} -> derived_product?(product) end)
        |> Enum.map(fn {product, months} ->
          %{
            product: product,
            months_quoted: months,
            suggested_species_id: best_species(product, species)
          }
        end)
        |> Enum.sort_by(& &1.product)

      {:ok, products}
    end
  end

  # The id of the species whose name best matches a product, at or above the threshold.
  defp best_species(product, species) do
    target = normalize(product)

    species
    |> Enum.map(&{&1.id, String.jaro_distance(target, normalize(&1.name))})
    |> Enum.max_by(&elem(&1, 1), fn -> nil end)
    |> case do
      {id, score} when score >= @suggest_threshold -> id
      _ -> nil
    end
  end

  @doc false
  # The best product for a species name at or above the threshold, or nil.
  def best_match(name, products) when is_binary(name) do
    target = normalize(name)

    products
    |> Enum.map(fn product ->
      %{product: product, score: Float.round(String.jaro_distance(target, normalize(product)), 2)}
    end)
    |> Enum.max_by(& &1.score, fn -> nil end)
    |> case do
      %{score: score} = match when score >= @suggest_threshold -> match
      _ -> nil
    end
  end

  def best_match(_name, _products), do: nil

  # "for processing" and "Organic-" rows are variants of a product already listed.
  defp derived_product?(product) do
    String.contains?(product, "for processing") or String.starts_with?(product, "Organic")
  end

  # Case-fold and crudely singularize so "Tomato" meets "Tomatoes", "Peach" "Peaches".
  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z ]/, "")
    |> String.trim()
    |> String.replace(~r/(oes|ches)$/, fn
      "oes" -> "o"
      "ches" -> "ch"
    end)
    |> String.replace(~r/s$/, "")
  end
end
