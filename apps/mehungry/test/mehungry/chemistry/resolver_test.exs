defmodule Mehungry.Chemistry.ResolverTest do
  # async: false — the resolver uses the shared global `:pubchem_cache`, which we
  # clear per test; serial runs keep the HTTP call-count assertions deterministic.
  use Mehungry.DataCase, async: false

  alias Mehungry.{Chemistry, Food}
  alias Mehungry.Chemistry.Resolver

  # A URL-routing stub for PUG REST that also counts calls, so tests can assert the
  # identifier-first short-circuit actually skips HTTP.
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
              %{"CID" => 971, "Synonym" => ["Oxalic acid", "oxalate", "CHEBI:16995", "144-62-7"]}
            ]
          }
        }
    end
  end

  describe "identifier-first resolution" do
    test "a MeSH id resolves, cross-references PubChem, and marks MeSH primary" do
      {:ok, compound} =
        Resolver.resolve(%{namespace: "mesh", identifier: "D000082", name: "acetaminophen"},
          source: "pubtator"
        )

      assert compound.name == "Oxalic acid"
      # Structural descriptors on the row; identifiers normalized into rows.
      assert compound.properties["molecular_formula"] == "C2H2O4"

      identifiers = Food.list_compound_identifiers(compound.id) |> Map.new(&{&1.namespace, &1})
      assert identifiers["mesh"].identifier == "D000082"
      assert identifiers["mesh"].is_primary
      assert identifiers["mesh"].source == "pubtator"
      # PubChem CID is a cross-reference, not the primary identity here.
      assert identifiers["pubchem"].identifier == "971"
      refute identifiers["pubchem"].is_primary
      assert identifiers["chebi"].identifier == "CHEBI:16995"
      assert identifiers["cas"].identifier == "144-62-7"
      assert identifiers["inchikey"].identifier == "MUBZPKHOEPUJKR-UHFFFAOYSA-N"
    end

    test "a known identifier short-circuits with no HTTP", %{calls: calls} do
      {:ok, first} = Resolver.resolve(%{namespace: "mesh", identifier: "D000082", name: "x"})
      after_first = calls.()

      {:ok, second} = Resolver.resolve(%{namespace: "mesh", identifier: "D000082", name: "x"})

      assert second.id == first.id
      assert calls.() == after_first, "expected the identifier lookup to skip HTTP"
    end

    test "an unresolvable MeSH id still creates a compound anchored on the MeSH id" do
      # No CID for this name → identity is the MeSH id alone.
      Application.put_env(:mehungry, :pubchem_http_adapter, fn url, _h, _o ->
        body =
          if String.contains?(url, "/cids"), do: %{"IdentifierList" => %{"CID" => []}}, else: %{}

        {:ok, %{status_code: 200, body: Jason.encode!(body), headers: []}}
      end)

      {:ok, compound} =
        Resolver.resolve(%{namespace: "mesh", identifier: "C999999", name: "novelchem"})

      assert [%{namespace: "mesh", identifier: "C999999", is_primary: true}] =
               Food.list_compound_identifiers(compound.id)
    end
  end

  describe "name-only fallback" do
    test "resolves via name_to_cids and makes PubChem CID primary" do
      {:ok, compound} = Resolver.resolve(%{name: "oxalic acid"})

      identifiers = Food.list_compound_identifiers(compound.id) |> Map.new(&{&1.namespace, &1})
      assert identifiers["pubchem"].identifier == "971"
      assert identifiers["pubchem"].is_primary
    end

    test "an unknown name returns :not_found and creates nothing" do
      Application.put_env(:mehungry, :pubchem_http_adapter, fn _url, _h, _o ->
        {:ok,
         %{
           status_code: 200,
           body: Jason.encode!(%{"IdentifierList" => %{"CID" => []}}),
           headers: []
         }}
      end)

      assert {:error, :not_found} = Resolver.resolve(%{name: "unobtainium"})
      assert Food.list_compounds() == []
    end

    test "no identifier and no name is :not_found" do
      assert {:error, :not_found} = Resolver.resolve(%{})
    end
  end

  test "a MeSH seed and a name-only import converge on one compound" do
    {:ok, by_name} = Resolver.resolve(%{name: "oxalate"})

    {:ok, by_mesh} =
      Chemistry.resolve(%{namespace: "mesh", identifier: "D000082", name: "oxalate"})

    assert by_name.id == by_mesh.id
    # Both anchors now hang off the single compound.
    identifiers = Food.list_compound_identifiers(by_name.id) |> Enum.map(& &1.namespace)
    assert "pubchem" in identifiers
    assert "mesh" in identifiers
  end
end
