defmodule Mehungry.Chemistry.PubChemTest do
  # async: false — the importer uses the shared global `:pubchem_cache`, which we
  # clear per test; serial runs keep the HTTP call-count assertions deterministic.
  use Mehungry.DataCase, async: false

  import Ecto.Query

  alias Mehungry.{Chemistry, Food, Repo}
  alias Mehungry.Chemistry.PubChem.RawResponse

  # A URL-routing stub for PUG REST that also counts calls, so tests can assert
  # the cache/idempotency short-circuits actually skip HTTP.
  setup do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Application.put_env(:mehungry, :pubchem_http_adapter, fn url, _headers, _opts ->
      Agent.update(counter, &(&1 + 1))
      {:ok, %{status_code: 200, body: Jason.encode!(response_body(url)), headers: []}}
    end)

    Cachex.clear(:pubchem_cache)

    on_exit(fn -> Application.delete_env(:mehungry, :pubchem_http_adapter) end)

    %{calls: fn -> Agent.get(counter, & &1) end}
  end

  defp response_body(url) do
    cond do
      String.contains?(url, "unobtainium") ->
        %{"IdentifierList" => %{"CID" => []}}

      String.contains?(url, "/cids") ->
        %{"IdentifierList" => %{"CID" => [971]}}

      String.contains?(url, "/property/") ->
        %{
          "PropertyTable" => %{
            "Properties" => [
              %{
                "CID" => 971,
                "Title" => "Oxalic acid",
                "IUPACName" => "oxalic acid",
                "MolecularFormula" => "C2H2O4",
                "CanonicalSMILES" => "C(=O)(C(=O)O)O",
                "IsomericSMILES" => "C(=O)(C(=O)O)O",
                "InChI" => "InChI=1S/C2H2O4/c3-1(4)2(5)6/h(H,3,4)(H,5,6)",
                "InChIKey" => "MUBZPKHOEPUJKR-UHFFFAOYSA-N"
              }
            ]
          }
        }

      String.contains?(url, "/synonyms") ->
        %{
          "InformationList" => %{
            "Information" => [
              %{
                "CID" => 971,
                "Synonym" => [
                  "Oxalic acid",
                  "oxalate",
                  "ethanedioic acid",
                  "CHEBI:16995",
                  "144-62-7"
                ]
              }
            ]
          }
        }
    end
  end

  test "three names for the same molecule converge to one canonical compound" do
    {:ok, c1} = Chemistry.import_compound("oxalic acid")
    {:ok, c2} = Chemistry.import_compound("oxalate")
    {:ok, c3} = Chemistry.import_compound("ethanedioic acid")

    assert c1.id == c2.id
    assert c2.id == c3.id

    compound = Food.get_compound!(c1.id)
    # Canonical name comes from PubChem's Title, not the fuzzy input.
    assert compound.name == "Oxalic acid"
    # Synonyms carry the requested alias plus PubChem's list.
    assert "oxalic acid" in compound.synonyms
    assert "oxalate" in compound.synonyms
    assert "ethanedioic acid" in compound.synonyms
    # Structural descriptors live in the properties jsonb.
    assert compound.properties["molecular_formula"] == "C2H2O4"
    assert compound.properties["smiles"] == "C(=O)(C(=O)O)O"
    assert compound.properties["inchi"] =~ "InChI=1S"
    # Cross-database identities are normalized into compound_identifiers rows.
    identifiers = Food.list_compound_identifiers(compound.id) |> Map.new(&{&1.namespace, &1})
    assert identifiers["pubchem"].identifier == "971"
    assert identifiers["pubchem"].is_primary
    assert identifiers["chebi"].identifier == "CHEBI:16995"
    assert identifiers["cas"].identifier == "144-62-7"
    # The InChIKey is a global identifier, so it lives with the identifiers.
    assert identifiers["inchikey"].identifier == "MUBZPKHOEPUJKR-UHFFFAOYSA-N"

    # One compound bears PubChem CID 971 across all three fuzzy names.
    assert Food.get_compound_by_identifier("pubchem", 971).id == compound.id
  end

  test "re-importing a known name performs no HTTP and returns the same compound", %{calls: calls} do
    {:ok, first} = Chemistry.import_compound("oxalate")
    after_first = calls.()

    {:ok, second} = Chemistry.import_compound("oxalate")

    assert second.id == first.id
    assert calls.() == after_first, "expected the cache to short-circuit all HTTP"
  end

  test "every raw PubChem payload is stored append-only" do
    {:ok, _} = Chemistry.import_compound("oxalate")

    endpoints = Repo.all(from r in RawResponse, select: r.endpoint)
    assert "name_cids" in endpoints
    assert "properties" in endpoints
    assert "synonyms" in endpoints
  end

  test "a pubchem provenance row is recorded, referencing the raw payload" do
    {:ok, compound} = Chemistry.import_compound("oxalate")

    assert [source] = Chemistry.list_compound_sources(compound.id)
    assert source.source_type == "pubchem"
    assert source.external_identifier == "971"
    assert source.last_synced_at
    assert source.raw_response_id
  end

  test "an unknown name returns :not_found, creates nothing, and caches the miss", %{calls: calls} do
    assert {:error, :not_found} = Chemistry.import_compound("unobtainium")
    assert Food.list_compounds() == []

    after_first = calls.()
    assert {:error, :not_found} = Chemistry.import_compound("unobtainium")
    assert calls.() == after_first, "expected the negative result to be cached"
  end

  test "compound_type defaults to \"other\"" do
    {:ok, compound} = Chemistry.import_compound("oxalate")
    assert compound.compound_type == "other"
  end

  test "compound_type is overridable for a newly created compound" do
    {:ok, compound} = Chemistry.import_compound("oxalate", compound_type: "oxalate")
    assert compound.compound_type == "oxalate"
  end
end
