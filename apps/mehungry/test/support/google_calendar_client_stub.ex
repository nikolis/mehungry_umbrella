defmodule Mehungry.Professionals.GoogleCalendar.ClientStub do
  @moduledoc """
  Test stand-in for the Google Calendar HTTP client, wired via the
  `:google_calendar_client` config key. Lets `Professionals`/worker tests
  push/delete events and import busy times without hitting Google.

  Each call sends `{:gcal, name, args}` to the process in the `:gcal_stub_pid`
  app env (default: the current process) so tests can assert what was invoked,
  and returns a canned success by default. Override any result with a
  `fn args -> result end` under `:gcal_stub_<name>`.
  """

  @behaviour Mehungry.Professionals.GoogleCalendar.ClientBehaviour

  @impl true
  def refresh_access_token(refresh_token) do
    dispatch(:refresh_access_token, refresh_token, fn ->
      {:ok, %{"access_token" => "ya29.stub", "expires_in" => 3600, "scope" => "calendar"}}
    end)
  end

  @impl true
  def insert_event(token, calendar_id, event) do
    dispatch(:insert_event, {token, calendar_id, event}, fn ->
      {:ok,
       %{
         "id" => "evt_stub_123",
         "hangoutLink" => "https://meet.google.com/stub-abc-def",
         "conferenceData" => %{
           "entryPoints" => [
             %{"entryPointType" => "video", "uri" => "https://meet.google.com/stub-abc-def"}
           ]
         }
       }}
    end)
  end

  @impl true
  def update_event(token, calendar_id, event_id, event) do
    dispatch(:update_event, {token, calendar_id, event_id, event}, fn ->
      {:ok, %{"id" => event_id}}
    end)
  end

  @impl true
  def delete_event(token, calendar_id, event_id) do
    dispatch(:delete_event, {token, calendar_id, event_id}, fn -> :ok end)
  end

  @impl true
  def free_busy(token, calendar_id, time_min, time_max) do
    dispatch(:free_busy, {token, calendar_id, time_min, time_max}, fn -> {:ok, []} end)
  end

  defp dispatch(name, args, default) do
    if pid = Application.get_env(:mehungry, :gcal_stub_pid), do: send(pid, {:gcal, name, args})

    case Application.get_env(:mehungry, :"gcal_stub_#{name}") do
      fun when is_function(fun, 1) -> fun.(args)
      _ -> default.()
    end
  end
end
