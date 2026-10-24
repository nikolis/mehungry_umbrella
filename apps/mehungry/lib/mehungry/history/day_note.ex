defmodule Mehungry.History.DayNote do
  @moduledoc """
  A private, free-text note a user attaches to a single calendar day — "how I
  felt today", symptoms, energy, anything. Deliberately condition-agnostic: no
  disease, no category, no structure. One row per `(user_id, date)`.

  This is the self-tracker's journal line: it lets someone correlate *what they
  ate* with *how they felt* without ever disclosing a condition to the app.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @max_body 2000

  schema "history_day_notes" do
    field :date, :date
    field :body, :string
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(day_note, attrs) do
    day_note
    |> cast(attrs, [:date, :body, :user_id])
    |> update_change(:body, &trim/1)
    |> validate_required([:date, :user_id])
    |> validate_length(:body, max: @max_body)
    |> unique_constraint([:user_id, :date])
  end

  defp trim(body) when is_binary(body), do: String.trim(body)
  defp trim(body), do: body
end
