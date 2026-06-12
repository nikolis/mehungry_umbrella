defmodule Mehungry.Feedback do
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Feedback.Feedback

  def change_feedback(attrs \\ %{}) do
    Feedback.changeset(%Feedback{}, attrs)
  end

  def create_feedback(attrs) do
    %Feedback{}
    |> Feedback.changeset(attrs)
    |> Repo.insert()
  end

  def list_feedbacks do
    Feedback
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def delete_feedback(%Feedback{} = feedback), do: Repo.delete(feedback)

  def get_feedback!(id), do: Repo.get!(Feedback, id)
end
