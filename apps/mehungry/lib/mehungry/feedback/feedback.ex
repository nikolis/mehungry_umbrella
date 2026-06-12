defmodule Mehungry.Feedback.Feedback do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feedbacks" do
    field :message, :string
    field :email, :string
    belongs_to :user, Mehungry.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:message, :email, :user_id])
    |> validate_required([:message])
    |> validate_length(:message, min: 10, max: 2000)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
  end
end
