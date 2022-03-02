defmodule MehungryApi.MeasurementUnitController do
  use MehungryApi, :controller

  alias Mehungry.Food
  alias Mehungry.Food.MeasurementUnit

  action_fallback(MehungryApi.FallbackController)

  def index(conn, _params) do
    measurement_units = Food.list_measurement_units()
    render(conn, "index.json", measurement_units: measurement_units)
  end

  def create(conn, %{"measurement_unit" => measurement_unit_params}) do
    with {:ok, %MeasurementUnit{} = measurement_unit} <-
           Food.create_measurement_unit(measurement_unit_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.measurement_unit_path(conn, :show, measurement_unit))
      |> render("show.json", measurement_unit: measurement_unit)
    end
  end

  def show(conn, %{"id" => id}) do
    measurement_unit = Food.get_measurement_unit!(id)
    render(conn, "show.json", measurement_unit: measurement_unit)
  end

  def search(conn, %{"name" => name, "language" => language}) do
    measurement_units = Food.search_measurement_unit(name, language)
    render(conn, "index.json", measurement_units: measurement_units)
  end

  def update(conn, %{"id" => id, "measurement_unit" => measurement_unit_params}) do
    measurement_unit = Food.get_measurement_unit!(id)

    with {:ok, %MeasurementUnit{} = measurement_unit} <-
           Food.update_measurement_unit(measurement_unit, measurement_unit_params) do
      render(conn, "show.json", measurement_unit: measurement_unit)
    end
  end

  def delete(conn, %{"id" => id}) do
    measurement_unit = Food.get_measurement_unit!(id)

    with {:ok, %MeasurementUnit{}} <- Food.delete_measurement_unit(measurement_unit) do
      send_resp(conn, :no_content, "")
    end
  end

  """
  def swagger_definitions do
    %{
      MeasurementUnit:
        swagger_schema do
          title("Measurement Unit")

          description(
            "Structs representing measurement units used to associate ingredients with recipes"
          )

          properties do
            name(:string, "The name of the measurement unit e.g grammar", required: true)
            translation(Schema.ref(:MeasurementUnitTranslation))
          end
        end,
      MeasurementUnitTranslation:
        swagger_schema do
          title("Measurement Unit Transalation")

          description(
            "Structs representing measurement units used to associate ingredients with recipes"
          )

          properties do
            name(
              :string,
              "The name of the measurement unit translated in the language infered e.g grammar",
              required: true
            )

            language(Schema.ref(:Language))
          end
        end,
      Language:
        swagger_schema do
          title("Language")
          description("Structs representing languages")

          properties do
            name(:string, "The abriviated name of the language E.g En or Gr", required: true)
          end
        end
    }
  end
  """
end
