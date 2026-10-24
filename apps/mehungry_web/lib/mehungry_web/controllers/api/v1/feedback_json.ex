defmodule MehungryWeb.Api.V1.FeedbackJSON do
  @moduledoc "Serializer for submitted feedback (spec §17)."

  import MehungryWeb.Api.V1.JSON.Helpers

  @doc "The created-feedback envelope returned by `POST /api/v1/feedback`."
  def show(%{feedback: feedback}) do
    data(%{
      id: feedback.id,
      message: feedback.message,
      email: feedback.email,
      user_id: feedback.user_id,
      submitted_at: utc(feedback.inserted_at)
    })
  end
end
