defmodule MehungryWeb.NutrientsFormatter do
  def format(nutrient_name) do
    nutrient_name
    |> MehungryWeb.FattyAcidFormatter.format()

    # |> MehungryWeb.VitaminsFormatter.format()
  end
end
