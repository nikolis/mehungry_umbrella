defmodule Mehungry.ObanWorkers.ModerationReportMailerWorker do
  @moduledoc """
  Emails the admin when a user reports content, off the request cycle on the
  `:mailers` queue, so reports can be reviewed within 24 hours (App Store
  Guideline 1.2). Enqueued by `Mehungry.Moderation.create_report/2`.

  The email goes only to the configured `:admin_email`. It names the reason and
  quotes the reported text, but not the reporter — that stays behind the admin
  login at `/professional/moderation`.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Mehungry.Mailer
  alias Mehungry.Moderation.ContentReport
  alias Mehungry.Repo

  @default_queue_url "https://www.m3hungry.com/professional/moderation"

  def enqueue(report_id) do
    %{"report_id" => report_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"report_id" => id}}) do
    case Repo.get(ContentReport, id) do
      # Resolved or purged before the job ran — nothing to announce.
      nil -> :ok
      %ContentReport{status: status} when status != "open" -> :ok
      report -> report |> build_email() |> Mailer.deliver() |> to_result()
    end
  end

  @doc false
  def build_email(%ContentReport{} = report) do
    url = Application.get_env(:mehungry, :moderation_queue_url, @default_queue_url)
    excerpt = report.snapshot |> to_string() |> String.slice(0, 500)

    text = """
    A user reported a #{report.target_type} (reason: #{report.reason}).

    Reported content:
    #{excerpt}

    Review it within 24 hours: #{url}
    """

    # `Swoosh.Email.new/0` would clash with the `new/1` Oban.Worker defines here.
    Swoosh.Email.new()
    |> Swoosh.Email.to(Application.get_env(:mehungry, :admin_email))
    |> Swoosh.Email.from({"Mehungry", "noreply@m3hungry.com"})
    |> Swoosh.Email.subject(
      "Content report ##{report.id}: #{report.target_type} — #{report.reason}"
    )
    |> Swoosh.Email.text_body(text)
  end

  defp to_result({:ok, _}), do: :ok
  defp to_result({:error, reason}), do: {:error, reason}
end
