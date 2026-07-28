defmodule Mehungry.Chemistry.PubChem.ClientTest do
  use ExUnit.Case, async: true

  alias Mehungry.Chemistry.PubChem.Client

  # Queue canned HTTP results; each adapter call pops the next, so a test can
  # script "503 then 200" retry sequences.
  defp stub_responses(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    Application.put_env(:mehungry, :pubchem_http_adapter, fn _url, _headers, _opts ->
      Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :pubchem_http_adapter) end)
  end

  defp ok(body, headers \\ []),
    do: {:ok, %{status_code: 200, body: Jason.encode!(body), headers: headers}}

  defp status(code, headers \\ []),
    do: {:ok, %{status_code: code, body: "", headers: headers}}

  describe "name_to_cids/1" do
    test "returns the first CID and surfaces etag/api_version meta" do
      stub_responses([
        ok(
          %{"IdentifierList" => %{"CID" => [971, 12345]}},
          [{"ETag", "abc"}, {"X-PubChem-Version", "2.2"}]
        )
      ])

      assert {:ok, 971, raw, %{etag: "abc", api_version: "2.2"}} =
               Client.name_to_cids("oxalate")

      assert get_in(raw, ["IdentifierList", "CID"]) == [971, 12345]
    end

    test "a name with no CID maps to :not_found" do
      stub_responses([ok(%{"IdentifierList" => %{"CID" => []}})])
      assert {:error, :not_found} = Client.name_to_cids("nonsense")
    end

    test "a 404 maps to :not_found" do
      stub_responses([status(404)])
      assert {:error, :not_found} = Client.name_to_cids("nope")
    end
  end

  describe "properties/1" do
    test "normalizes the property row (accepts CanonicalSMILES for SMILES)" do
      stub_responses([
        ok(%{
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
        })
      ])

      assert {:ok, props, _raw, _meta} = Client.properties(971)
      assert props.title == "Oxalic acid"
      assert props.molecular_formula == "C2H2O4"
      assert props.smiles == "C(=O)(C(=O)O)O"
      assert props.inchikey == "MUBZPKHOEPUJKR-UHFFFAOYSA-N"
    end
  end

  describe "synonyms/1" do
    test "returns the synonym list" do
      stub_responses([
        ok(%{
          "InformationList" => %{
            "Information" => [
              %{"CID" => 971, "Synonym" => ["oxalic acid", "Oxalate", "CHEBI:16995"]}
            ]
          }
        })
      ])

      assert {:ok, ["oxalic acid", "Oxalate", "CHEBI:16995"], _raw, _meta} = Client.synonyms(971)
    end

    test "an empty synonym payload yields an empty list, not an error" do
      stub_responses([ok(%{"Fault" => %{}})])
      assert {:ok, [], _raw, _meta} = Client.synonyms(971)
    end
  end

  describe "retry / throttle" do
    test "a 503 with a short Retry-After is absorbed in-process and then succeeds" do
      stub_responses([
        status(503, [{"Retry-After", "0"}]),
        ok(%{"IdentifierList" => %{"CID" => [971]}})
      ])

      assert {:ok, 971, _raw, _meta} = Client.name_to_cids("oxalate")
    end

    test "a 503 with a long Retry-After is surfaced for the caller to back off" do
      stub_responses([status(503, [{"Retry-After", "300"}])])
      assert {:error, {:rate_limited, 300}} = Client.name_to_cids("oxalate")
    end

    test "persistent 503s surface as rate_limited after exhausting inline retries" do
      stub_responses([
        status(503, [{"Retry-After", "0"}]),
        status(503, [{"Retry-After", "0"}]),
        status(503, [{"Retry-After", "0"}])
      ])

      assert {:error, {:rate_limited, _}} = Client.name_to_cids("oxalate")
    end

    test "a network error is retried and can recover" do
      stub_responses([
        {:error, %HTTPoison.Error{reason: :timeout}},
        ok(%{"IdentifierList" => %{"CID" => [971]}})
      ])

      assert {:ok, 971, _raw, _meta} = Client.name_to_cids("oxalate")
    end
  end
end
