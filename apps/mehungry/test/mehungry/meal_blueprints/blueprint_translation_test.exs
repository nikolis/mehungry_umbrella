defmodule Mehungry.MealBlueprints.BlueprintTranslationTest do
  @moduledoc """
  Blueprints as a translation-hub resource: the generic descriptor-driven
  upsert/verify path and the read-time `localize_blueprints/2` overlay.
  """
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Languages.{Translations, TranslationRegistry}
  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.Presets

  @locale "el"

  defp descriptor, do: TranslationRegistry.get("meal_blueprints")

  defp blueprint_fixture(attrs \\ %{}) do
    user = user_fixture()
    {:ok, bp} = Presets.create_for_user(user.id, :female, :regular, 30)

    {:ok, bp} =
      bp
      |> Ecto.Changeset.change(Map.merge(%{name: "Balanced Week"}, attrs))
      |> Repo.update()

    bp
  end

  test "the blueprint descriptor is registered with name + description fields" do
    d = descriptor()
    assert d.key == "meal_blueprints"
    assert d.fields == [:name, :description]
    assert d.ai == :fields
    assert d.fk == :blueprint_id
  end

  test "the generic hub path upserts and verifies a blueprint translation" do
    bp = blueprint_fixture(%{description: "A balanced 7-day week."})

    {:ok, _} =
      Translations.upsert(descriptor(), bp.id, @locale, %{
        name: "Ισορροπημένη Εβδομάδα",
        description: "Μια ισορροπημένη εβδομάδα."
      })

    pair = Translations.get_pair(descriptor(), bp.id, @locale)
    assert pair.translation.name == "Ισορροπημένη Εβδομάδα"
    assert pair.translation.status == "verified"
  end

  describe "localize_blueprints/2" do
    test "overlays a verified translation for the target locale" do
      bp = blueprint_fixture(%{description: "English summary."})

      {:ok, _} =
        Translations.upsert(descriptor(), bp.id, @locale, %{
          name: "Ελληνικό όνομα",
          description: "Ελληνική περιγραφή."
        })

      [localized] = MealBlueprints.localize_blueprints([bp], @locale)
      assert localized.name == "Ελληνικό όνομα"
      assert localized.description == "Ελληνική περιγραφή."
    end

    test "leaves the source locale untouched" do
      bp = blueprint_fixture()
      assert MealBlueprints.localize_blueprint(bp, "en").name == bp.name
    end

    test "ignores an unverified AI draft (drafts never reach a public page)" do
      bp = blueprint_fixture()

      {:ok, _} =
        Translations.upsert(descriptor(), bp.id, @locale, %{name: "Πρόχειρο"}, status: "ai_draft")

      assert MealBlueprints.localize_blueprint(bp, @locale).name == bp.name
    end

    test "passes an untranslated blueprint through unchanged" do
      bp = blueprint_fixture()
      assert MealBlueprints.localize_blueprint(bp, @locale).name == bp.name
    end
  end
end
