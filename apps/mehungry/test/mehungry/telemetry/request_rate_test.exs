defmodule Mehungry.Telemetry.RequestRateTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Repo
  alias Mehungry.Telemetry.{RequestRate, Snapshot}

  doctest RequestRate

  defp snapshot(route, sample_count, avg, minutes_ago) do
    period_start =
      DateTime.utc_now()
      |> DateTime.add(-minutes_ago * 60, :second)
      |> DateTime.truncate(:second)

    Repo.insert!(%Snapshot{
      metric: "phoenix.request.duration",
      tags: %{"route" => route},
      period_start: period_start,
      min: avg,
      avg: avg,
      max: avg,
      p95: avg,
      sample_count: sample_count
    })
  end

  test "sums requests per route and computes per-minute rate over the window" do
    snapshot("/api/local_ai/pending", 30, 10.0, 3)
    snapshot("/api/local_ai/pending", 30, 20.0, 8)
    snapshot("/api/local_ai/full_text", 6, 100.0, 4)

    result = RequestRate.local_ai(3600)

    pending = Enum.find(result.routes, &(&1.route == "/api/local_ai/pending"))
    full_text = Enum.find(result.routes, &(&1.route == "/api/local_ai/full_text"))

    assert pending.requests == 60
    # 60 requests over a 60-minute window == 1.0/min
    assert pending.per_min == 1.0
    # sample-count-weighted avg latency: (30*10 + 30*20) / 60
    assert pending.avg_ms == 15.0
    # newest window (3 min ago) had 30 samples -> 30/5
    assert pending.latest_5m_per_min == 6.0

    assert full_text.requests == 6
    assert full_text.per_min == 0.1

    assert result.total.requests == 66
    # routes are sorted busiest first
    assert [%{route: "/api/local_ai/pending"} | _] = result.routes
  end

  test "excludes non-local-ai routes and snapshots outside the window" do
    snapshot("/api/local_ai/pending", 10, 5.0, 2)
    snapshot("/recipes/:id", 500, 5.0, 2)
    snapshot("/api/local_ai/pending", 999, 5.0, 120)

    result = RequestRate.local_ai(3600)

    assert [route] = result.routes
    assert route.route == "/api/local_ai/pending"
    assert route.requests == 10
    assert result.total.requests == 10
  end

  test "returns an empty, well-formed shape when there is no traffic" do
    result = RequestRate.local_ai(3600)

    assert result.routes == []
    assert result.total == %{requests: 0, per_min: 0.0}
    assert is_binary(result.generated_at)
    assert Map.has_key?(result.live, :per_min)
  end
end
