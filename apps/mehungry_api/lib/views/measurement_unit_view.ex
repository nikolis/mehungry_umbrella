defmodule MehungryApi.MeasurementUnitView do
  use MehungryApi, :view
  alias MehungryApi.MeasurementUnitView

  def render("index.json", %{measurement_units: measurement_units}) do
    %{data: render_many(measurement_units, MeasurementUnitView, "measurement_unit.json")}
  end

  def render("show.json", %{measurement_unit: measurement_unit}) do
    %{data: render_one(measurement_unit, MeasurementUnitView, "measurement_unit.json")}
  end

  def render("measurement_unit.json", %{measurement_unit: measurement_unit}) do
    %{id: measurement_unit.id, url: measurement_unit.url, name: measurement_unit.name}
  end
end
