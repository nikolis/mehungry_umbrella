defmodule Mehungry.Literature.FullTextIntegrityTest do
  use ExUnit.Case, async: true

  alias Mehungry.Literature.FullTextIntegrity, as: FTI

  describe "classify/1 — provenance verdict" do
    test "in the OA subset → verified (regardless of licence)" do
      assert FTI.classify(%{found?: true, oa?: true, license: "cc-by"}) == :verified
      assert FTI.classify(%{found?: true, oa?: true, license: "cc-by-nc-nd"}) == :verified
    end

    test "not OA and no licence at all → mismatch (clear-cut purge)" do
      assert FTI.classify(%{found?: true, oa?: false, license: "unknown"}) == :mismatch
    end

    test "not OA but carries a real licence → pending_review (ambiguous)" do
      assert FTI.classify(%{found?: true, oa?: false, license: "cc-by"}) == :pending_review
      assert FTI.classify(%{found?: true, oa?: false, license: "cc-by-nc-nd"}) == :pending_review
    end

    test "lookup inconclusive → pending_review" do
      assert FTI.classify(%{found?: false, oa?: false, license: "unknown"}) == :pending_review
    end
  end

  describe "decision/1 — integrity + display gate" do
    test "verified + reusable licence → displayable" do
      d = FTI.decision(%{found?: true, oa?: true, license: "cc-by", license_url: nil, pmcid: "PMC1"})
      assert d == %{integrity_status: "verified", full_text_displayable: true}
    end

    test "verified but non-reusable licence → kept, not displayable" do
      d = FTI.decision(%{found?: true, oa?: true, license: "cc-by-nc", license_url: nil, pmcid: "PMC1"})
      assert d == %{integrity_status: "verified", full_text_displayable: false}
    end

    test "mismatch → not displayable" do
      d = FTI.decision(%{found?: true, oa?: false, license: "unknown", license_url: nil, pmcid: nil})
      assert d == %{integrity_status: "mismatch", full_text_displayable: false}
    end
  end

  describe "verify/1 via stubbed client" do
    defmodule StubClient do
      @behaviour Mehungry.Literature.FullTextIntegrity.ClientBehaviour
      @impl true
      def lookup("26380705"), do: {:ok, %{oa?: true, license: "CC BY", license_url: nil, pmcid: "PMC4567880"}}
      def lookup("2122965"), do: {:ok, %{oa?: false, license: nil, license_url: nil, pmcid: nil}}
      def lookup("boom"), do: {:error, :timeout}
    end

    setup do
      prev = Application.get_env(:mehungry, :europepmc_client)
      Application.put_env(:mehungry, :europepmc_client, StubClient)
      on_exit(fn -> Application.put_env(:mehungry, :europepmc_client, prev) end)
    end

    test "resolves + normalizes a CC-BY OA paper" do
      v = FTI.verify("26380705")
      assert v.oa? and v.license == "cc-by" and v.pmcid == "PMC4567880"
      assert FTI.classify(v) == :verified
    end

    test "a confirmed neighbor-substitution (not OA, no licence) → mismatch" do
      v = FTI.verify("2122965")
      assert FTI.classify(v) == :mismatch
    end

    test "transport error → not_found → pending_review" do
      v = FTI.verify("boom")
      refute v.found?
      assert FTI.classify(v) == :pending_review
    end
  end
end
