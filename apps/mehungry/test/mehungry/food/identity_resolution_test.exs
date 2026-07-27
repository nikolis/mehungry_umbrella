defmodule Mehungry.Food.IdentityResolutionTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Food.IdentityResolution
  alias Mehungry.Food.IngredientScientificIdentity
  alias Mehungry.Repo

  # Deterministic stub sources swapped in via the app-env seams.
  defmodule SpinachUsdaStub do
    def fetch_scientific_name(999_001),
      do: {:ok, %{scientific_name: "Spinacia oleracea", description: "Spinach, raw", data_type: "Foundation"}, %{remaining: 100}}

    def fetch_scientific_name(_other),
      do: {:ok, %{scientific_name: nil, description: "Mystery", data_type: "Foundation"}, %{remaining: 100}}
  end

  defmodule SpinachIdStub do
    @behaviour Mehungry.Food.IdentityResolution.ScientificIdClient
    @impl true
    def resolve("Spinacia oleracea") do
      {:ok,
       %{
         ncbi_taxonomy_id: 3562,
         foodon_id: "FOODON:00003278",
         wikidata_id: "Q37937",
         rank: "species",
         id_source: "wikidata",
         synonyms: [%{name: "spinach", synonym_type: "common_name", source: "wikidata"}]
       }}
    end

    def resolve(_), do: {:ok, %{}}
  end

  defp use_sources(usda, id_client) do
    Application.put_env(:mehungry, :usda_scientific_source, usda)
    Application.put_env(:mehungry, :scientific_id_client, id_client)

    on_exit(fn ->
      Application.delete_env(:mehungry, :usda_scientific_source)
      Application.delete_env(:mehungry, :scientific_id_client)
    end)
  end

  defp candidate_attrs(ingredient, overrides \\ %{}) do
    Map.merge(
      %{
        ingredient_id: ingredient.id,
        scientific_name: "Spinacia oleracea",
        source: "usda_fdc",
        confidence: 0.9,
        status: "candidate"
      },
      overrides
    )
  end

  describe "add_identity_candidate/1 (never overwrite)" do
    test "creates then finds; the same natural key is never duplicated or mutated" do
      ing = ingredient_fixture(%{name: "spinach"})

      {:ok, first, :created} = IdentityResolution.add_identity_candidate(candidate_attrs(ing, %{confidence: 0.9}))
      {:ok, second, :exists} = IdentityResolution.add_identity_candidate(candidate_attrs(ing, %{confidence: 0.1}))

      assert first.id == second.id
      # The existing row is returned untouched — the new (lower) confidence is ignored.
      assert second.confidence == 0.9
      assert [_only] = IdentityResolution.list_identities(ing.id)
    end

    test "supports multiple distinct candidates per ingredient" do
      ing = ingredient_fixture(%{name: "spinach"})

      {:ok, _, :created} = IdentityResolution.add_identity_candidate(candidate_attrs(ing))

      {:ok, _, :created} =
        IdentityResolution.add_identity_candidate(
          candidate_attrs(ing, %{scientific_name: "Spinacia sp.", source: "manual"})
        )

      assert length(IdentityResolution.list_identities(ing.id)) == 2
    end
  end

  describe "verification workflow (history-preserving)" do
    test "verifying a second identity supersedes the first and chains history" do
      reviewer1 = user_fixture()
      reviewer2 = user_fixture()
      ing = ingredient_fixture(%{name: "spinach"})
      {:ok, a, _} = IdentityResolution.add_identity_candidate(candidate_attrs(ing))

      {:ok, b, _} =
        IdentityResolution.add_identity_candidate(
          candidate_attrs(ing, %{scientific_name: "Spinacia sp.", source: "manual"})
        )

      {:ok, _} = IdentityResolution.verify_identity(a.id, reviewer1.id)
      {:ok, _} = IdentityResolution.verify_identity(b.id, reviewer2.id)

      a_reloaded = Repo.get!(IngredientScientificIdentity, a.id)
      b_reloaded = Repo.get!(IngredientScientificIdentity, b.id)

      # A was verified then superseded by B; nothing was deleted.
      assert a_reloaded.status == "superseded"
      assert a_reloaded.superseded_by_id == b.id
      assert b_reloaded.status == "verified"
      assert b_reloaded.verified_by_user_id == reviewer2.id
      assert IdentityResolution.verified_identity(ing.id).id == b.id
    end

    test "the DB enforces at most one verified identity per ingredient" do
      ing = ingredient_fixture(%{name: "spinach"})
      {:ok, a, _} = IdentityResolution.add_identity_candidate(candidate_attrs(ing))

      {:ok, b, _} =
        IdentityResolution.add_identity_candidate(
          candidate_attrs(ing, %{scientific_name: "Spinacia sp.", source: "manual"})
        )

      {:ok, _} = IdentityResolution.verify_identity(a.id)
      {:ok, _} = IdentityResolution.verify_identity(b.id)

      verified =
        Repo.all(
          from(x in IngredientScientificIdentity,
            where: x.ingredient_id == ^ing.id and x.status == "verified"
          )
        )

      assert length(verified) == 1
    end

    test "reject keeps the row for history" do
      ing = ingredient_fixture(%{name: "spinach"})
      {:ok, a, _} = IdentityResolution.add_identity_candidate(candidate_attrs(ing))

      {:ok, rejected} = IdentityResolution.reject_identity(a.id, 1)

      assert rejected.status == "rejected"
      assert Repo.get!(IngredientScientificIdentity, a.id).status == "rejected"
    end
  end

  describe "synonyms" do
    test "attach per identity; list across an ingredient's identities" do
      ing = ingredient_fixture(%{name: "spinach"})
      {:ok, identity, _} = IdentityResolution.add_identity_candidate(candidate_attrs(ing))

      {:ok, _} =
        IdentityResolution.add_synonym(%{
          scientific_identity_id: identity.id,
          name: "spinach",
          synonym_type: "common_name",
          source: "wikidata"
        })

      # Idempotent on the natural key.
      {:ok, _} =
        IdentityResolution.add_synonym(%{
          scientific_identity_id: identity.id,
          name: "spinach",
          synonym_type: "common_name",
          source: "wikidata"
        })

      assert [syn] = IdentityResolution.list_synonyms(identity.id)
      assert syn.name == "spinach"
      assert [_] = IdentityResolution.list_synonyms_for_ingredient(ing.id)
    end
  end

  describe "resolve_ingredient/1 (orchestration)" do
    test "resolves spinach end-to-end from stubbed USDA + id sources" do
      use_sources(SpinachUsdaStub, SpinachIdStub)
      ing = ingredient_fixture(%{name: "spinach", fdc_id: 999_001})

      assert {:ok, :matched} = Food.resolve_ingredient(ing)

      assert [identity] = IdentityResolution.list_identities(ing.id)
      assert identity.scientific_name == "Spinacia oleracea"
      assert identity.ncbi_taxonomy_id == 3562
      assert identity.foodon_id == "FOODON:00003278"
      assert identity.wikidata_id == "Q37937"
      assert identity.id_source == "wikidata"
      assert identity.source == "usda_fdc"
      assert identity.confidence == 0.9

      assert [%{name: "spinach"}] = IdentityResolution.list_synonyms(identity.id)

      # Re-running does not duplicate.
      assert {:ok, :matched} = Food.resolve_ingredient(ing)
      assert length(IdentityResolution.list_identities(ing.id)) == 1
    end

    test "records a no_scientific_name attempt and creates no identity when USDA has none" do
      use_sources(SpinachUsdaStub, SpinachIdStub)
      ing = ingredient_fixture(%{name: "mystery", fdc_id: 424_242})

      assert {:ok, :no_scientific_name} = Food.resolve_ingredient(ing)
      assert IdentityResolution.list_identities(ing.id) == []

      # The attempt ledger recorded it, so a batch would not re-select it.
      assert IdentityResolution.list_unresolved_ingredients(50) |> Enum.all?(&(&1.id != ing.id))
    end
  end
end
