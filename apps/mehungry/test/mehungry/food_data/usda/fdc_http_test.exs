defmodule Mehungry.FoodData.Usda.FdcHttpTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Usda.FdcHttp

  # Queue a list of canned HTTP results; each call to the stubbed adapter pops
  # the next one, so a test can script "429 then 200" style retry sequences.
  defp stub_responses(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    Application.put_env(:mehungry, :fdc_http_adapter, fn _url, _headers, _opts ->
      Agent.get_and_update(agent, fn [next | rest] -> {next, rest} end)
    end)

    on_exit(fn -> Application.delete_env(:mehungry, :fdc_http_adapter) end)
  end

  defp ok(body, headers \\ []),
    do: {:ok, %{status_code: 200, body: Jason.encode!(body), headers: headers}}

  defp status(code, headers \\ []),
    do: {:ok, %{status_code: code, body: "", headers: headers}}

  test "parses body and x-ratelimit-remaining on 200" do
    stub_responses([ok(%{"foods" => []}, [{"X-RateLimit-Remaining", "42"}])])

    assert {:ok, %{"foods" => []}, %{remaining: 42}} = FdcHttp.get("http://fdc")
  end

  test "remaining is nil when the header is absent" do
    stub_responses([ok(%{"ok" => true})])

    assert {:ok, %{"ok" => true}, %{remaining: nil}} = FdcHttp.get("http://fdc")
  end

  test "404 maps to :not_found" do
    stub_responses([status(404)])

    assert {:error, :not_found} = FdcHttp.get("http://fdc")
  end

  test "a 429 with a short Retry-After is absorbed in-process and then succeeds" do
    stub_responses([
      status(429, [{"Retry-After", "0"}]),
      ok(%{"recovered" => true}, [{"x-ratelimit-remaining", "9"}])
    ])

    assert {:ok, %{"recovered" => true}, %{remaining: 9}} = FdcHttp.get("http://fdc")
  end

  test "a 429 with a long Retry-After is surfaced immediately for the caller to snooze" do
    stub_responses([status(429, [{"Retry-After", "300"}])])

    assert {:error, {:rate_limited, 300}} = FdcHttp.get("http://fdc")
  end

  test "persistent 429s surface as rate_limited after exhausting inline retries" do
    stub_responses([
      status(429, [{"Retry-After", "0"}]),
      status(429, [{"Retry-After", "0"}]),
      status(429, [{"Retry-After", "0"}])
    ])

    assert {:error, {:rate_limited, _}} = FdcHttp.get("http://fdc")
  end

  test "a 5xx is retried and can recover" do
    stub_responses([status(500), ok(%{"recovered" => true})])

    assert {:ok, %{"recovered" => true}, _meta} = FdcHttp.get("http://fdc")
  end

  test "a persistent 5xx surfaces as {:http, code} after retries" do
    stub_responses([status(503), status(503), status(503)])

    assert {:error, {:http, 503}} = FdcHttp.get("http://fdc")
  end

  test "a network error is retried and can recover" do
    stub_responses([
      {:error, %HTTPoison.Error{reason: :timeout}},
      ok(%{"recovered" => true})
    ])

    assert {:ok, %{"recovered" => true}, _meta} = FdcHttp.get("http://fdc")
  end

  test "a non-retryable 4xx surfaces as {:http, code}" do
    stub_responses([status(403)])

    assert {:error, {:http, 403}} = FdcHttp.get("http://fdc")
  end
end
