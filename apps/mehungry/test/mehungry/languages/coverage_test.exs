defmodule Mehungry.Languages.CoverageTest do
  use Mehungry.DataCase

  alias Mehungry.Food
  alias Mehungry.Food.CompoundTranslation
  alias Mehungry.Languages.{Coverage, Translations, TranslationRegistry}
  alias Mehungry.Repo

  @locale "el"

  defp compounds_descriptor, do: TranslationRegistry.get("compounds")

  defp make_compound(name) do
    {:ok, c} = Food.create_compound(%{name: name, compound_type: "other"})
    c
  end

  defp coverage do
    Coverage.coverage(compounds_descriptor(), @locale)
  end

  describe "coverage math" do
    test "counts verified / ai_draft / missing and computes pct" do
      c1 = make_compound("Oxalate")
      c2 = make_compound("Lectin")
      _c3 = make_compound("Phytate")

      assert %{total: 3, verified: 0, ai_draft: 0, missing: 3, pct: 0} = coverage()

      # A machine draft.
      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c1.id, @locale, %{name: "Οξαλικό"},
          status: "ai_draft"
        )

      # A human-verified translation.
      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c2.id, @locale, %{name: "Λεκτίνη"},
          status: "verified"
        )

      cov = coverage()
      assert cov.total == 3
      assert cov.verified == 1
      assert cov.ai_draft == 1
      assert cov.missing == 1
      assert cov.pct == 33
    end

    test "a base with both a draft and a verified row counts once, as verified" do
      c = make_compound("Histamine")

      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c.id, @locale, %{name: "draft"},
          status: "ai_draft"
        )

      # Upserting again over the same (id, el) row flips it to verified.
      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c.id, @locale, %{name: "verified"},
          status: "verified"
        )

      cov = coverage()
      assert cov.verified == 1
      assert cov.ai_draft == 0
      assert cov.missing == 0
    end

    test "legacy Gr rows count toward the el locale (bridge)" do
      c = make_compound("Purine")
      Mehungry.Languages.ensure_language("Gr")

      # A pre-existing legacy translation, written under the old "Gr" code.
      Repo.insert!(%CompoundTranslation{
        compound_id: c.id,
        language_name: "Gr",
        name: "Πουρίνη",
        status: "verified"
      })

      cov = coverage()
      assert cov.verified == 1
      assert cov.missing == 0
    end
  end

  describe "Translations list + verify" do
    test "list_items filters by status" do
      c1 = make_compound("A")
      c2 = make_compound("B")

      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c1.id, @locale, %{name: "α"},
          status: "ai_draft"
        )

      missing = Translations.list_items(compounds_descriptor(), @locale, filter: :missing)
      draft = Translations.list_items(compounds_descriptor(), @locale, filter: :ai_draft)

      assert Enum.map(missing, & &1.base.id) == [c2.id]
      assert Enum.map(draft, & &1.base.id) == [c1.id]
      assert hd(draft).translation.name == "α"
    end

    test "verify flips a draft to verified and stamps audit fields" do
      c = make_compound("C")

      {:ok, _} =
        Translations.upsert(compounds_descriptor(), c.id, @locale, %{name: "γ"},
          status: "ai_draft"
        )

      {:ok, verified} = Translations.verify(compounds_descriptor(), c.id, @locale)

      assert verified.status == "verified"
      assert verified.verified_at != nil
      assert coverage().verified == 1
    end

    test "verify with no translation yet returns error" do
      c = make_compound("D")
      assert {:error, :not_found} = Translations.verify(compounds_descriptor(), c.id, @locale)
    end
  end
end
