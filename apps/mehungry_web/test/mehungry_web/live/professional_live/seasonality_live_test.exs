defmodule MehungryWeb.ProfessionalLive.SeasonalityLiveTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Food

  @admin_email Application.compile_env(:mehungry, :admin_email)

  # Peaches are quoted every week of June–August 2025; the portal knows two products.
  defmodule AgridataStub do
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

    # The country's whole catalogue: peaches (2 months) and tomatoes (1 month).
    def quotes(_country, _years, nil) do
      row = fn variety, date ->
        %{
          "variety" => variety,
          "productStage" => "Farmgate price",
          "periodType" => "Week",
          "beginDate" => date
        }
      end

      {:ok,
       [
         row.("Peaches - All", "02/06/2025"),
         row.("Peaches - All", "07/07/2025"),
         row.("Tomatoes - Round", "06/01/2025")
       ]}
    end

    def quotes(_country, _years, _product), do: {:ok, []}
    def products, do: {:ok, ["Peaches", "Tomatoes"]}
  end

  # 500 t imported in September 2025, all from Turkey.
  defmodule ComextStub do
    def monthly_imports(_country, _code, _since, _until) do
      {:ok,
       %{
         "id" => ["partner", "time"],
         "size" => [2, 1],
         "value" => %{"0" => 5000, "1" => 5000},
         "dimension" => %{
           "partner" => %{"category" => %{"index" => %{"WORLD" => 0, "TR" => 1}}},
           "time" => %{"category" => %{"index" => %{"2025-09" => 0}}}
         }
       }}
    end
  end

  setup %{conn: conn} do
    Application.put_env(:mehungry_seasonality, :agridata_client, AgridataStub)
    Application.put_env(:mehungry_seasonality, :comext_client, ComextStub)

    on_exit(fn ->
      Application.delete_env(:mehungry_seasonality, :agridata_client)
      Application.delete_env(:mehungry_seasonality, :comext_client)
    end)

    {:ok, peach} = Food.create_foundemental_species(%{"name" => "Peach"})
    admin = user_fixture(%{email: @admin_email})

    %{conn: log_in_user(conn, admin), peach: peach}
  end

  defp add_mapping(view, species, source, code) do
    view
    |> form("#add-mapping-form", %{
      "mapping" => %{"species_id" => species.id, "source" => source, "external_code" => code}
    })
    |> render_submit()
  end

  test "is admin-only", %{peach: _peach} do
    conn = log_in_user(build_conn(), user_fixture())
    assert {:error, {:redirect, _}} = live(conn, ~p"/professional/seasonality")
  end

  test "renders the enabled countries and an empty state", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/professional/seasonality")

    assert html =~ "Fetch Greece"
    assert html =~ "No species mapped yet."
    assert has_element?(view, "nav a", "Cyprus")
  end

  test "lists available foods without a mapping and maps one", %{conn: conn, peach: peach} do
    {:ok, view, _html} = live(conn, ~p"/professional/seasonality?country=GR")
    html = render_async(view)

    assert html =~ "Available foods without a mapping — Greece"
    # most-quoted first; peach has a species, tomato does not
    assert html =~ ~r/available-Peaches.*available-Tomatoes/s
    assert has_element?(view, "#available-Peaches", "species exists")
    assert has_element?(view, "#available-Peaches", "quoted in 2 of 12 months")
    assert has_element?(view, "#available-Tomatoes", "no species yet")

    view
    |> form("#available-Peaches form", %{"species_id" => peach.id})
    |> render_submit()

    refute has_element?(view, "#available-Peaches")
    assert has_element?(view, "#available-Tomatoes")
    assert has_element?(view, "#seasonality-mappings li", "Peaches")
  end

  test "suggests, applies, adds and removes mappings", %{conn: conn, peach: peach} do
    {:ok, view, _html} = live(conn, ~p"/professional/seasonality")

    view |> element("button", "Run suggester") |> render_click()
    assert has_element?(view, "#seasonality-suggestions li", "Peaches")

    view |> element("#seasonality-suggestions button", "Apply") |> render_click()
    refute has_element?(view, "#seasonality-suggestions")
    assert has_element?(view, "#seasonality-mappings li", "Peaches")

    add_mapping(view, peach, "comext", "080930")
    assert has_element?(view, "#seasonality-mappings li", "080930")

    assert add_mapping(view, peach, "comext", "peaches") =~ "must be a 2–8 digit HS/CN code"

    view |> element("button[aria-label='Remove 080930']") |> render_click()
    refute has_element?(view, "#seasonality-mappings li", "080930")
  end

  test "fetches a country and shows local + import facts per month", %{conn: conn, peach: peach} do
    {:ok, view, _html} = live(conn, ~p"/professional/seasonality")
    add_mapping(view, peach, "agridata", "Peaches")
    add_mapping(view, peach, "comext", "080930")

    view |> element("button", "Fetch Greece") |> render_click()
    assert render_async(view) =~ "Fetch started"
    assert has_element?(view, "#seasonality-rows", "pending")

    assert %{success: 1} = Oban.drain_queue(queue: :seasonality)
    html = render(view)

    assert has_element?(view, "#seasonality-rows", "completed")
    assert html =~ "12 local · 12 import months"

    assert has_element?(view, "#cell-#{peach.id}-7[data-local='in_season'][data-imported='none']")
    assert has_element?(view, "#cell-#{peach.id}-9[data-local='none'][data-imported='major']")
    assert has_element?(view, "#cell-#{peach.id}-1[data-local='none'][data-imported='none']")

    assert view |> element("#cell-#{peach.id}-9") |> render() =~ "500 t/month, from TR 100%"
  end

  test "refuses to fetch with nothing mapped", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/seasonality")

    view |> element("button", "Fetch Greece") |> render_click()
    assert render_async(view) =~ "Map at least one species to a product first"
  end

  test "overrides a month by hand and clears it again", %{conn: conn, peach: peach} do
    {:ok, _} =
      MehungrySeasonality.save_mapping(%{
        foundemental_species_id: peach.id,
        source: "agridata",
        external_code: "Peaches"
      })

    {:ok, _batch} = MehungrySeasonality.fetch_country("GR")
    Oban.drain_queue(queue: :seasonality)

    {:ok, view, _html} = live(conn, ~p"/professional/seasonality?country=GR")
    assert has_element?(view, "#cell-#{peach.id}-1[data-local='none']")

    view |> element("#cell-#{peach.id}-1") |> render_click()
    assert has_element?(view, "#override-form")

    view
    |> form("#override-form", %{"override" => %{"local" => "stored", "note" => "cold store"}})
    |> render_submit()

    assert has_element?(view, "#cell-#{peach.id}-1[data-local='stored']")
    assert view |> element("#cell-#{peach.id}-1") |> render() =~ "cold store"

    view |> element("#cell-#{peach.id}-1") |> render_click()
    view |> element("button", "Clear override") |> render_click()
    assert has_element?(view, "#cell-#{peach.id}-1[data-local='none']")
  end

  test "each country keeps its own results", %{conn: conn, peach: peach} do
    {:ok, _} =
      MehungrySeasonality.save_mapping(%{
        foundemental_species_id: peach.id,
        source: "agridata",
        external_code: "Peaches"
      })

    {:ok, _batch} = MehungrySeasonality.fetch_country("GR")
    Oban.drain_queue(queue: :seasonality)

    {:ok, view, _html} = live(conn, ~p"/professional/seasonality?country=IT")

    assert render(view) =~ "Fetch Italy"
    assert has_element?(view, "#cell-#{peach.id}-7[data-local='unknown']")
  end
end
