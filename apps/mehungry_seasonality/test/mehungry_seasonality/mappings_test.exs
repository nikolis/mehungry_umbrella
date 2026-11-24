defmodule MehungrySeasonality.MappingsTest do
  use MehungrySeasonality.Case, async: false

  alias MehungrySeasonality.Mappings

  test "saves, lists and deletes mappings" do
    id = species_fixture("Peach")

    assert {:ok, mapping} =
             MehungrySeasonality.save_mapping(%{
               foundemental_species_id: id,
               source: "comext",
               external_code: " 080930 "
             })

    assert mapping.external_code == "080930"
    assert [%{id: mapping_id}] = MehungrySeasonality.list_mappings()
    assert {:ok, _} = MehungrySeasonality.delete_mapping(mapping_id)
    assert MehungrySeasonality.list_mappings() == []
    assert {:error, :not_found} = MehungrySeasonality.delete_mapping(mapping_id)
  end

  test "rejects a duplicate, an unknown source and a malformed Comext code" do
    id = species_fixture("Peach")
    attrs = %{foundemental_species_id: id, source: "comext", external_code: "080930"}

    assert {:ok, _} = MehungrySeasonality.save_mapping(attrs)
    assert {:error, changeset} = MehungrySeasonality.save_mapping(attrs)
    assert %{foundemental_species_id: ["is already mapped"]} = errors(changeset)

    assert {:error, _} = MehungrySeasonality.save_mapping(%{attrs | source: "faostat"})
    assert {:error, _} = MehungrySeasonality.save_mapping(%{attrs | external_code: "peaches"})
  end

  test "suggests agri-food products only for species without one" do
    peach = species_fixture("Peach")
    tomato = species_fixture("Tomato")
    _quinoa = species_fixture("Quinoa")
    map_species(tomato, agridata: "Tomatoes")

    assert {:ok, suggestions} = MehungrySeasonality.suggest_mappings()
    assert %{product: "Peaches"} = suggestions[peach]
    refute Map.has_key?(suggestions, tomato)
    assert map_size(suggestions) == 1
  end

  test "reports an unreachable product list" do
    Application.put_env(
      :mehungry_seasonality,
      :agridata_client,
      MehungrySeasonality.TestStubs.Failing
    )

    assert {:error, :timeout} = MehungrySeasonality.suggest_mappings()
  end

  test "lists the products with a local signal for a country, with a species hint" do
    peach = species_fixture("Peach")
    map_species(peach, agridata: "Peaches")

    assert {:ok, products} = MehungrySeasonality.available_products("GR")

    # Retail-only (Lemons), processing and organic variants are left out; a mapped
    # product is still listed — the caller decides what to hide.
    assert products == [
             %{product: "Peaches", months_quoted: 2, suggested_species_id: peach},
             %{product: "Tomatoes", months_quoted: 1, suggested_species_id: nil}
           ]
  end

  test "available_products reports an unreachable portal" do
    Application.put_env(
      :mehungry_seasonality,
      :agridata_client,
      MehungrySeasonality.TestStubs.Failing
    )

    assert {:error, :timeout} = MehungrySeasonality.available_products("GR")
  end

  test "best_match never offers processing or weak matches" do
    assert %{product: "Tomatoes"} = Mappings.best_match("Tomato", ["Tomatoes", "Peaches"])
    assert Mappings.best_match("Quinoa", ["Tomatoes", "Peaches"]) == nil
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
