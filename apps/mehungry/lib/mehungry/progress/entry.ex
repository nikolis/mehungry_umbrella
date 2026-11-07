defmodule Mehungry.Progress.Entry do
  @moduledoc """
  A dated diary entry inside a self-tracking `Progress.Period`: the user's own
  measurements (same numeric vocabulary as a nutritionist's `ConsultationNote`)
  plus a free-text note. One entry per date per period (unique index) — logging
  the same day again upserts.

  `bmi`/`bmr_kcal` are derived at write time from the period's anthropometric
  snapshot (`Anthropometrics`), never typed by the user. `user_id` is
  denormalized from the period for IDOR-safe ownership scoping.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "progress_entries" do
    field :entry_date, :date
    field :weight_kg, :float
    field :waist_cm, :float
    field :body_fat_percentage, :float
    field :muscle_mass_kg, :float
    field :bmi, :float
    field :bmr_kcal, :integer
    field :note, :string

    belongs_to :period, Mehungry.Progress.Period, foreign_key: :progress_period_id
    belongs_to :user, Mehungry.Accounts.User
    has_many :photos, Mehungry.Progress.Photo, foreign_key: :progress_entry_id

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :progress_period_id,
      :user_id,
      :entry_date,
      :weight_kg,
      :waist_cm,
      :body_fat_percentage,
      :muscle_mass_kg,
      :bmi,
      :bmr_kcal,
      :note
    ])
    |> validate_required([:progress_period_id, :user_id, :entry_date])
    |> validate_number(:weight_kg, greater_than: 0)
    |> validate_number(:body_fat_percentage,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:waist_cm, greater_than: 0)
    |> validate_number(:muscle_mass_kg, greater_than: 0)
    |> foreign_key_constraint(:progress_period_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:progress_period_id, :entry_date])
  end
end
