defmodule MehungryWeb.NutritionistLive.AnalyticsLive do
  @moduledoc """
  Earnings & pipeline dashboard for a nutritionist. Answers the three things a
  solo practice acts on: am I getting paid, is my calendar full, where am I
  leaking money. Everything is read from the `professional_payments` ledger via
  `Mehungry.Professionals` aggregates (SQL GROUP BY — no rows loaded here), using
  the ledger's own net formula so totals can never drift from the ledger.

  Revenue is deliberately broken down by *what was sold and how it resolved*
  (service · new-vs-returning · outcome) — never by client demographics
  (age/gender/condition): at single-digit client counts that discloses per-client
  earnings and treats GDPR Article 9 health data for a new purpose. See
  docs/features/professionals/analytics.md.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias VegaLite, as: Vl

  @basil "#45C4AE"
  @axis_label "#94A3B8"
  @axis_domain "#334155"
  @grid "#1E293B"

  @ranges ~w(week month all)
  @dimensions ~w(service returning outcome)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Analytics")
      |> assign(:range, "month")
      |> assign(:dimension, "service")

    socket = if connected?(socket), do: load_analytics(socket), else: assign_placeholders(socket)
    {:ok, socket}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, socket |> assign(:range, range) |> load_analytics()}
  end

  def handle_event("set_dimension", %{"dim" => dim}, socket) when dim in @dimensions do
    {:noreply, socket |> assign(:dimension, dim) |> load_analytics()}
  end

  # VegaLite hook fires this on window resize; specs size to :container so there
  # is nothing to recompute — swallow it.
  def handle_event("resize_chart", _params, socket), do: {:noreply, socket}
  def handle_event(_evt, _params, socket), do: {:noreply, socket}

  # ── Data loading ────────────────────────────────────────────────────────────

  defp load_analytics(socket) do
    pid = socket.assigns.current_user.id
    range = socket.assigns.range
    dr = date_range(range)

    net = Professionals.net_earnings_cents(pid, dr)
    in_flight = Professionals.in_flight_cents(pid)
    outcome = Professionals.revenue_by_outcome(pid, dr)
    revenue_series = Professionals.revenue_per_period(pid, dr, granularity(range))
    appts_series = Professionals.appointments_per_week(pid, 8)
    breakdown = breakdown_rows(socket.assigns.dimension, pid, dr)

    socket
    |> assign(:net_cents, net)
    |> assign(:in_flight_cents, in_flight)
    |> assign(:pending_count, Professionals.count_pending_requests(pid))
    |> assign(:client_count, Professionals.count_clients(pid))
    |> assign(:appts_this_week, this_week_count(appts_series))
    |> assign(:outcome, outcome)
    |> assign(:breakdown, breakdown)
    |> assign(:has_revenue?, net > 0 or in_flight > 0)
    |> assign(:leakage?, outcome.refunded_cents > 0 or outcome.released_cents > 0)
    |> assign(:revenue_spec, build_revenue_spec(revenue_series))
    |> assign(:appts_spec, build_appts_spec(appts_series))
    |> assign(:breakdown_spec, build_breakdown_spec(breakdown))
  end

  # Dead-render skeleton (zeros / empty specs) — the connected mount replaces it.
  defp assign_placeholders(socket) do
    empty = %{captured_cents: 0, no_show_cents: 0, refunded_cents: 0, released_cents: 0}

    socket
    |> assign(:net_cents, 0)
    |> assign(:in_flight_cents, 0)
    |> assign(:pending_count, 0)
    |> assign(:client_count, 0)
    |> assign(:appts_this_week, 0)
    |> assign(:outcome, empty)
    |> assign(:breakdown, [])
    |> assign(:has_revenue?, false)
    |> assign(:leakage?, false)
    |> assign(:revenue_spec, build_revenue_spec([]))
    |> assign(:appts_spec, build_appts_spec([]))
    |> assign(:breakdown_spec, build_breakdown_spec([]))
  end

  defp breakdown_rows("service", pid, dr) do
    Professionals.revenue_by_service(pid, dr)
    |> Enum.map(fn r -> %{label: service_label(r), net_cents: r.net_cents} end)
    |> fold_top_n(6)
  end

  defp breakdown_rows("returning", pid, dr) do
    %{new_cents: n, returning_cents: r} = Professionals.revenue_new_vs_returning(pid, dr)
    [%{label: "New clients", net_cents: n}, %{label: "Returning clients", net_cents: r}]
  end

  defp breakdown_rows("outcome", pid, dr) do
    o = Professionals.revenue_by_outcome(pid, dr)

    [
      %{label: "Captured", net_cents: o.captured_cents},
      %{label: "No-show retained", net_cents: o.no_show_cents},
      %{label: "Refunded", net_cents: o.refunded_cents},
      %{label: "Released", net_cents: o.released_cents}
    ]
  end

  defp service_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp service_label(%{kind: "intro"}), do: "Intro session"
  defp service_label(%{kind: "package"}), do: "Package"
  defp service_label(%{kind: "session"}), do: "Session"
  defp service_label(_), do: "Other / direct"

  # Keep the top N rows by net, fold the rest into one "Other" row.
  defp fold_top_n(rows, n) when length(rows) <= n, do: rows

  defp fold_top_n(rows, n) do
    {top, rest} = Enum.split(rows, n)
    other = Enum.reduce(rest, 0, &(&1.net_cents + &2))
    top ++ [%{label: "Other", net_cents: other}]
  end

  defp this_week_count([]), do: 0

  defp this_week_count(series) do
    case List.last(series) do
      %{count: c} -> c
      _ -> 0
    end
  end

  # ── Date ranges ───────────────────────────────────────────────────────────────
  # NOTE: boundaries are computed in UTC. Times are stored UTC end-to-end today;
  # per-nutritionist timezone resolution is a documented follow-up.

  defp date_range("all"), do: :all

  defp date_range("week") do
    today = Date.utc_today()
    start = Date.beginning_of_week(today, :monday)
    {NaiveDateTime.new!(start, ~T[00:00:00]), end_of_today()}
  end

  defp date_range("month") do
    today = Date.utc_today()
    start = Date.beginning_of_month(today)
    {NaiveDateTime.new!(start, ~T[00:00:00]), end_of_today()}
  end

  defp end_of_today, do: NaiveDateTime.new!(Date.utc_today(), ~T[23:59:59])

  defp granularity("all"), do: :month
  defp granularity(_), do: :day

  # ── Chart specs (basil marks, slate axes — matches the nutritionist section) ───

  defp build_revenue_spec(series) do
    data =
      Enum.map(series, fn %{period: p, net_cents: c} ->
        %{"period" => period_label(p), "euros" => euros_value(c)}
      end)

    Vl.new(width: :container, height: 200, autosize: [type: "fit", contains: "padding"])
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, color: @basil, corner_radius_end: 3, tooltip: true)
    |> Vl.encode_field(:x, "period",
      type: :ordinal,
      axis: [
        label_angle: -35,
        title: nil,
        label_color: @axis_label,
        domain_color: @axis_domain,
        tick_color: @axis_domain
      ]
    )
    |> Vl.encode_field(:y, "euros",
      type: :quantitative,
      title: "€ net",
      axis: [
        title_color: @axis_label,
        label_color: @axis_label,
        domain_color: @axis_domain,
        grid_color: @grid
      ]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_appts_spec(series) do
    data =
      Enum.map(series, fn %{period: p, count: c} ->
        %{"week" => period_label(p), "count" => c}
      end)

    Vl.new(width: :container, height: 120, autosize: [type: "fit", contains: "padding"])
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, color: @basil, corner_radius_end: 3, tooltip: true)
    |> Vl.encode_field(:x, "week",
      type: :ordinal,
      axis: [
        label_angle: -35,
        title: nil,
        label_color: @axis_label,
        domain_color: @axis_domain,
        tick_color: @axis_domain
      ]
    )
    |> Vl.encode_field(:y, "count",
      type: :quantitative,
      title: nil,
      axis: [label_color: @axis_label, domain_color: @axis_domain, grid_color: @grid]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  defp build_breakdown_spec(rows) do
    data =
      Enum.map(rows, fn %{label: l, net_cents: c} ->
        %{"label" => l, "euros" => euros_value(c)}
      end)

    Vl.new(
      width: :container,
      height: max(120, length(rows) * 34),
      autosize: [type: "fit", contains: "padding"]
    )
    |> Vl.data_from_values(data)
    |> Vl.mark(:bar, color: @basil, corner_radius_end: 3, tooltip: true)
    |> Vl.encode_field(:y, "label",
      type: :nominal,
      sort: "-x",
      title: nil,
      axis: [label_color: @axis_label, domain_color: @axis_domain, tick_color: @axis_domain]
    )
    |> Vl.encode_field(:x, "euros",
      type: :quantitative,
      title: "€ net",
      axis: [
        title_color: @axis_label,
        label_color: @axis_label,
        domain_color: @axis_domain,
        grid_color: @grid
      ]
    )
    |> Vl.config(background: "transparent", view: [stroke: nil])
    |> Vl.to_spec()
  end

  # date_trunc returns a NaiveDateTime; label its date for the axis.
  defp period_label(%NaiveDateTime{} = ndt),
    do: ndt |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp period_label(%Date{} = d), do: Date.to_iso8601(d)
  defp period_label(other), do: to_string(other)

  defp euros_value(cents) when is_integer(cents), do: Float.round(cents / 100, 2)
  defp euros_value(_), do: 0.0

  # ── View helpers (used by the template) ───────────────────────────────────────

  def euros(nil), do: "€0.00"

  def euros(cents) when is_integer(cents),
    do: "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  def range_label("week"), do: "This week"
  def range_label("month"), do: "This month"
  def range_label("all"), do: "All time"

  def ranges, do: @ranges
  def dimensions, do: @dimensions

  def dimension_label("service"), do: "By service"
  def dimension_label("returning"), do: "New vs returning"
  def dimension_label("outcome"), do: "By outcome"
end
