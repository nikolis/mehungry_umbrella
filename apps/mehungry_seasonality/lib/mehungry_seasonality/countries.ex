defmodule MehungrySeasonality.Countries do
  @moduledoc """
  The countries seasonality can be fetched for. Countries are identified by ISO-3166
  alpha-2 code everywhere in this app (`"GR"`); the per-source code differences live
  here (the EU agri-food portal calls Greece `"EL"`, Eurostat Comext calls it `"GR"`).

  Which of the known countries are **enabled** is configuration:
  `config :mehungry_seasonality, countries: ~w(GR CY IT ES DE)`.
  """

  # iso => {name, agri-food portal member-state code, Comext reporter code}
  @known %{
    "AT" => {"Austria", "AT", "AT"},
    "BE" => {"Belgium", "BE", "BE"},
    "BG" => {"Bulgaria", "BG", "BG"},
    "CY" => {"Cyprus", "CY", "CY"},
    "CZ" => {"Czechia", "CZ", "CZ"},
    "DE" => {"Germany", "DE", "DE"},
    "DK" => {"Denmark", "DK", "DK"},
    "EE" => {"Estonia", "EE", "EE"},
    "ES" => {"Spain", "ES", "ES"},
    "FI" => {"Finland", "FI", "FI"},
    "FR" => {"France", "FR", "FR"},
    "GR" => {"Greece", "EL", "GR"},
    "HR" => {"Croatia", "HR", "HR"},
    "HU" => {"Hungary", "HU", "HU"},
    "IE" => {"Ireland", "IE", "IE"},
    "IT" => {"Italy", "IT", "IT"},
    "LT" => {"Lithuania", "LT", "LT"},
    "LU" => {"Luxembourg", "LU", "LU"},
    "LV" => {"Latvia", "LV", "LV"},
    "MT" => {"Malta", "MT", "MT"},
    "NL" => {"Netherlands", "NL", "NL"},
    "PL" => {"Poland", "PL", "PL"},
    "PT" => {"Portugal", "PT", "PT"},
    "RO" => {"Romania", "RO", "RO"},
    "SE" => {"Sweden", "SE", "SE"},
    "SI" => {"Slovenia", "SI", "SI"},
    "SK" => {"Slovakia", "SK", "SK"}
  }

  @default ~w(GR)

  @doc "Enabled countries as `%{code, name}` maps, in configured order."
  def supported do
    :mehungry_seasonality
    |> Application.get_env(:countries, @default)
    |> Enum.filter(&Map.has_key?(@known, &1))
    |> Enum.map(fn code -> %{code: code, name: name(code)} end)
  end

  @doc "True when the ISO code is an enabled country."
  def supported?(code), do: Enum.any?(supported(), &(&1.code == code))

  @doc "Display name for an ISO code (the code itself when unknown)."
  def name(code) do
    case Map.get(@known, code) do
      {name, _, _} -> name
      nil -> code
    end
  end

  @doc "The EU agri-food portal member-state code for an ISO code."
  def agridata_code(code), do: @known |> Map.fetch!(code) |> elem(1)

  @doc "The Eurostat Comext reporter code for an ISO code."
  def comext_code(code), do: @known |> Map.fetch!(code) |> elem(2)
end
