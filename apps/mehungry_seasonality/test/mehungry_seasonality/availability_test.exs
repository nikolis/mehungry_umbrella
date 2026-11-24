defmodule MehungrySeasonality.AvailabilityTest do
  use MehungrySeasonality.Case

  alias MehungrySeasonality.MonthStatus

  defp status(species_id, month, local, attrs \\ %{}) do
    %MonthStatus{}
    |> MonthStatus.changeset(
      Map.merge(
        %{
          foundemental_species_id: species_id,
          country: "GR",
          month: month,
          local: local,
          imported: "none"
        },
        attrs
      )
    )
    |> Mehungry.Repo.insert!()
  end

  test "species locally on the market count; none / unknown do not" do
    peach = species_fixture("Peach")
    apple = species_fixture("Apple")
    lemon = species_fixture("Lemon")
    kiwi = species_fixture("Kiwi")
    melon = species_fixture("Melon")

    status(peach, 7, "in_season")
    status(apple, 7, "unresolved")
    status(lemon, 7, "stored")
    status(kiwi, 7, "none")
    status(melon, 7, "unknown")
    status(peach, 1, "none")

    assert MehungrySeasonality.available_species_ids("GR", 7) == MapSet.new([peach, apple, lemon])
    assert MehungrySeasonality.available_species_ids("GR", 1) == MapSet.new()
    assert MehungrySeasonality.available_species_ids("IT", 7) == MapSet.new()
  end

  test "an admin override is the effective value" do
    tomato = species_fixture("Tomato")
    status(tomato, 2, "unresolved")

    {:ok, _} =
      MehungrySeasonality.override_status(%{species_id: tomato, country: "GR", month: 2}, %{
        "local" => "none"
      })

    refute MapSet.member?(MehungrySeasonality.available_species_ids("GR", 2), tomato)
  end

  test "core's seam reads this app through MehungrySeasonality.Core" do
    peach = species_fixture("Peach")
    status(peach, 7, "in_season")

    previous = Application.get_env(:mehungry, :seasonal_availability)
    Application.put_env(:mehungry, :seasonal_availability, MehungrySeasonality.Core)
    on_exit(fn -> Application.put_env(:mehungry, :seasonal_availability, previous) end)

    assert Mehungry.Food.SeasonalAvailability.available_species_ids("GR", 7) ==
             MapSet.new([peach])

    assert "GR" in Mehungry.Food.SeasonalAvailability.supported_country_codes()
  end
end
