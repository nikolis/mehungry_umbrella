defmodule Mehungry.Food.SeasonalAvailabilityTest do
  # Swaps the global :seasonal_availability config — not async.
  use Mehungry.DataCase, async: false

  import Mehungry.FoodFixtures, only: [ingredient_fixture: 1]

  alias Mehungry.Food
  alias Mehungry.Food.{FoundementalFood, SeasonalAvailability, SnackIngredients}
  alias Mehungry.Repo

  # A stand-in for the seasonality app: species ids come from the test process.
  defmodule Stub do
    @behaviour Mehungry.Food.SeasonalAvailability

    @impl true
    def available_species_ids("GR", 7),
      do: Application.get_env(:mehungry, :stub_species, MapSet.new())

    def available_species_ids(_country, _month), do: MapSet.new()

    @impl true
    def supported_countries, do: [%{code: "GR", name: "Greece"}, %{code: "IT", name: "Italy"}]
  end

  setup do
    previous = Application.get_env(:mehungry, :seasonal_availability)

    on_exit(fn ->
      Application.delete_env(:mehungry, :stub_species)

      if previous,
        do: Application.put_env(:mehungry, :seasonal_availability, previous),
        else: Application.delete_env(:mehungry, :seasonal_availability)
    end)

    :ok
  end

  defp use_impl(module), do: Application.put_env(:mehungry, :seasonal_availability, module)

  defp curated_onto_species(ingredient, name) do
    {:ok, species} = Food.create_foundemental_species(%{name: name})

    Repo.insert!(%FoundementalFood{
      foundemental_species_id: species.id,
      ingredient_id: ingredient.id,
      usda_name: ingredient.name
    })

    species
  end

  describe "with the Noop default" do
    setup do
      use_impl(SeasonalAvailability.Noop)
      :ok
    end

    test "knows no seasons and offers only Greece" do
      assert SeasonalAvailability.available_species_ids("GR", 7) == MapSet.new()
      assert SeasonalAvailability.available_ingredient_ids("GR", 7) == MapSet.new()
      assert SeasonalAvailability.supported_country_codes() == ["GR"]
    end

    test "an unloadable configured module falls back to Noop" do
      use_impl(Does.Not.Exist)
      assert SeasonalAvailability.supported_country_codes() == ["GR"]
    end
  end

  describe "with an implementation" do
    setup do
      use_impl(Stub)
      peach = ingredient_fixture(%{name: "Peaches, raw"})
      apple = ingredient_fixture(%{name: "Apples, raw"})
      peach_species = curated_onto_species(peach, "Peach #{System.unique_integer([:positive])}")
      _apple_species = curated_onto_species(apple, "Apple #{System.unique_integer([:positive])}")
      Application.put_env(:mehungry, :stub_species, MapSet.new([peach_species.id]))

      %{peach: peach, apple: apple}
    end

    test "maps available species to their curated ingredients", %{peach: peach} do
      assert SeasonalAvailability.available_ingredient_ids("GR", 7) == MapSet.new([peach.id])
      assert SeasonalAvailability.available_ingredient_ids("GR", 1) == MapSet.new()
    end

    test "seasonal fruit = curated fresh fruit ∩ in season", %{peach: peach, apple: apple} do
      {:ok, _} = SnackIngredients.add(peach.id, "fresh_fruit")
      {:ok, _} = SnackIngredients.add(apple.id, "fresh_fruit")
      # A nut entry for the same ingredient must not leak into the fruit set.
      {:ok, _} = SnackIngredients.add(apple.id, "dried_nut")

      assert Food.seasonal_fruit_ids("GR", 7) == MapSet.new([peach.id])
      assert Food.seasonal_fruit_ids("GR", 1) == MapSet.new()
    end

    test "a curated fruit that is in season but not curated as fruit is not offered", %{
      peach: peach
    } do
      {:ok, _} = SnackIngredients.add(peach.id, "dried_nut")
      assert Food.seasonal_fruit_ids("GR", 7) == MapSet.new()
    end

    test "profile country must be a supported code" do
      changeset =
        Mehungry.Accounts.UserProfile.changeset(%Mehungry.Accounts.UserProfile{}, %{
          user_id: 1,
          country: "FR"
        })

      assert %{country: [_]} = errors_on(changeset)

      changeset =
        Mehungry.Accounts.UserProfile.changeset(%Mehungry.Accounts.UserProfile{}, %{
          user_id: 1,
          country: "IT"
        })

      refute Map.has_key?(errors_on(changeset), :country)
    end
  end
end
