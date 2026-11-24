defmodule MehungrySeasonality.TestStubs do
  @moduledoc """
  Hand-written stand-ins for the two API clients, swapped in per test with
  `Application.put_env(:mehungry_seasonality, :agridata_client | :comext_client, …)`.
  """

  defmodule Agridata do
    @moduledoc "Peaches are quoted every week of June–August 2025; nothing else is."
    @behaviour MehungrySeasonality.Agridata.ClientBehaviour

    @impl true
    def quotes(_country, _years, "Peaches") do
      rows =
        for date <- Date.range(~D[2025-06-02], ~D[2025-08-25], 7) do
          %{
            "productStage" => "Farmgate price",
            "periodType" => "Week",
            "beginDate" => Calendar.strftime(date, "%d/%m/%Y")
          }
        end

      {:ok, rows}
    end

    # Every product of the country: two producer-quoted, one retail-only.
    def quotes(_country, _years, nil) do
      row = fn variety, stage, date ->
        %{
          "variety" => variety,
          "productStage" => stage,
          "periodType" => "Week",
          "beginDate" => date
        }
      end

      {:ok,
       [
         row.("Peaches - Yellow flesh", "Farmgate price", "02/06/2025"),
         row.("Peaches - White flesh", "Ex-packaging station price", "02/06/2025"),
         row.("Peaches - All types and varieties", "Farmgate price", "04/08/2025"),
         row.("Peaches for processing - All", "Farmgate price", "14/07/2025"),
         row.("Tomatoes - Round", "Ex-packaging station price", "06/01/2025"),
         row.("Organic-Tomatoes - Round", "Ex-packaging station price", "06/01/2025"),
         row.("Lemons - All", "Retail buying price", "06/01/2025")
       ]}
    end

    def quotes(_country, _years, _product), do: {:ok, []}

    @impl true
    def products,
      do: {:ok, ["Peaches", "Tomatoes", "Lemons", "Peaches for processing", "Organic-Tomatoes"]}
  end

  defmodule Comext do
    @moduledoc "September imports of 500 t, all from Turkey; 2 t in January."
    @behaviour MehungrySeasonality.Comext.ClientBehaviour

    @impl true
    def monthly_imports(_country, _code, _since, _until) do
      {:ok,
       %{
         "id" => ["partner", "time"],
         "size" => [2, 2],
         "value" => %{"0" => 20, "1" => 5000, "3" => 5000},
         "dimension" => %{
           "partner" => %{"category" => %{"index" => %{"WORLD" => 0, "TR" => 1}}},
           "time" => %{"category" => %{"index" => %{"2025-01" => 0, "2025-09" => 1}}}
         }
       }}
    end
  end

  defmodule Failing do
    @moduledoc "Both APIs are down."

    def quotes(_country, _years, _product), do: {:error, :timeout}
    def products, do: {:error, :timeout}
    def monthly_imports(_country, _code, _since, _until), do: {:error, :timeout}
  end
end
