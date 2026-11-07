defmodule Mehungry.Progress.Period do
  @moduledoc """
  A self-tracking **progress period** — the first-class unit of the user's own
  progress journal, identified by its date range (`started_on`..`ended_on`,
  `ended_on == nil` = active/ongoing). A user has **at most one active period**
  (DB partial unique index `progress_periods_one_active_per_user`).

  Two kinds:

    * `"self"` — the user logs their own diary entries (`Progress.Entry`) with
      whichever metrics they chose to track (`tracked_metrics`) against their
      own `goals`.
    * `"nutritionist_aligned"` — opened automatically when the user is assigned
      a nutritionist (`professional_id` set); self-logging is paused and the
      period's chart is fed by the nutritionist's intake/visit measurements
      instead. Closed (and a fresh `"self"` period opened) on unassignment.

  `height_m`/`sex`/`age` are an optional anthropometric snapshot captured at
  goal setup so BMI (and BMR, when age is known) can be derived for users who
  never had a nutritionist intake. `shared_with_nutritionist` lets the user
  opt-in to showing the period to their assigned nutritionist.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Professionals.Anthropometrics

  @kinds ~w(self nutritionist_aligned)
  @selectable_metrics ~w(weight_kg waist_cm body_fat_percentage muscle_mass_kg)

  def kinds, do: @kinds

  @doc "The metric keys a user may choose to track (BMI/BMR are derived, never selected)."
  def selectable_metrics, do: @selectable_metrics

  schema "progress_periods" do
    field :kind, :string, default: "self"
    field :started_on, :date
    field :ended_on, :date
    field :tracked_metrics, {:array, :string}, default: ["weight_kg"]
    field :goals, :map, default: %{}
    field :shared_with_nutritionist, :boolean, default: false
    field :title, :string
    field :notes, :string
    field :height_m, :float
    field :sex, :string
    field :age, :integer

    belongs_to :user, Mehungry.Accounts.User
    belongs_to :professional, Mehungry.Accounts.User
    has_many :entries, Mehungry.Progress.Entry, foreign_key: :progress_period_id

    timestamps()
  end

  def changeset(period, attrs) do
    period
    |> cast(attrs, [
      :user_id,
      :kind,
      :professional_id,
      :started_on,
      :ended_on,
      :tracked_metrics,
      :goals,
      :shared_with_nutritionist,
      :title,
      :notes,
      :height_m,
      :sex,
      :age
    ])
    |> validate_required([:user_id, :kind, :started_on])
    |> validate_inclusion(:kind, @kinds)
    |> validate_subset(:tracked_metrics, @selectable_metrics)
    |> validate_inclusion(:sex, Anthropometrics.sex_values())
    |> validate_number(:height_m, greater_than: 0)
    |> validate_number(:age, greater_than: 0, less_than: 130)
    |> validate_goals()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:professional_id)
    |> unique_constraint(:user_id,
      name: :progress_periods_one_active_per_user,
      message: "already has an active period"
    )
  end

  # Goals must be a %{metric => positive number} map over the selectable metrics.
  defp validate_goals(changeset) do
    validate_change(changeset, :goals, fn :goals, goals ->
      valid? =
        is_map(goals) and
          Enum.all?(goals, fn
            {k, v} when k in @selectable_metrics and is_number(v) and v > 0 -> true
            _ -> false
          end)

      if valid?, do: [], else: [goals: "must map tracked metrics to positive numbers"]
    end)
  end
end
