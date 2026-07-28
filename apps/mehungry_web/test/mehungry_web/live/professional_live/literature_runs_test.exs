defmodule MehungryWeb.ProfessionalLive.LiteratureRunsTest do
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Literature.AnnotationRun
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.CrawlRun
  alias Mehungry.Literature.CrawlRuns

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    %{conn: log_in_user(conn, admin)}
  end

  test "renders both pipeline sections idle", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/professional/literature")

    assert html =~ "Literature"
    assert html =~ "Paper discovery (Entrez/PubMed crawl)"
    assert html =~ "Entity annotation (PubTator3)"
    assert html =~ "Run crawl"
    assert html =~ "Run annotation"
    assert html =~ "Idle"
  end

  test "Run crawl opens a crawl run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/literature")

    assert CrawlRuns.latest_run() == nil

    html = view |> element("button", "Run crawl") |> render_click()

    assert html =~ "Crawl started"
    run = CrawlRuns.latest_run()
    assert run.status in ["pending", "processing", "completed"]
    assert_enqueued(worker: Mehungry.ObanWorkers.LiteratureCrawlWorker)
  end

  test "Run annotation opens an annotation run and enqueues the worker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/literature")

    assert AnnotationRuns.latest_run() == nil

    html = view |> element("button", "Run annotation") |> render_click()

    assert html =~ "Annotation started"
    run = AnnotationRuns.latest_run()
    assert run.status in ["pending", "processing", "completed"]
    assert_enqueued(worker: Mehungry.ObanWorkers.PubTatorAnnotationWorker)
  end

  test "a broadcast run update moves the crawl progress bar live", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/literature")

    run = %CrawlRun{status: "processing", processed: 1, total: 2}
    Phoenix.PubSub.broadcast(Mehungry.PubSub, CrawlRuns.topic(), {:literature_crawl_run, run})

    html = render(view)
    assert html =~ "1 / 2 (50%)"
    assert html =~ "Running…"
  end

  test "a broadcast run update moves the annotation progress bar live", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/professional/literature")

    run = %AnnotationRun{status: "completed", processed: 4, total: 4}
    Phoenix.PubSub.broadcast(Mehungry.PubSub, AnnotationRuns.topic(), {:pubtator_annotation_run, run})

    html = render(view)
    assert html =~ "4 / 4 (100%)"
    assert html =~ "Completed"
  end

  test "non-admin is redirected away", %{} do
    conn = build_conn()
    user = user_fixture(%{email: "notadmin@example.com"})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/literature")
  end
end
