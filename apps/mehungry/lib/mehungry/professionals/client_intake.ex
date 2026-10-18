defmodule Mehungry.Professionals.ClientIntake do
  @moduledoc """
  A baseline dietary-history assessment for a `ProfessionalClient` (the intake
  form filled at the first appointment).

  Anthropometric and energy figures are typed columns (queryable); the rest of
  the questionnaire — medical history, lifestyle, eating behavior, and the
  24-hour recall — lives in the free-form JSONB `details` map under the known
  keys documented below. Modeled `has_many` off the client (keyed by
  `assessed_on`) so a client can be re-assessed over time.

  Known `details` keys: `reason_for_visit`, `weight_fluctuations`,
  `marital_status`, `milestone_events`, `past_attempts`, `family_weight_history`,
  `hereditary_conditions`, `gi_function`, `medications`, `blood_biochem`,
  `thyroid_tests`, `gynecological_history`, `allergies`, `alcohol`, `fluids`,
  `smoking`, `sleep`, `physical_activity`, `food_intolerances`, `food_aversions`,
  `special_eating_habits`, `unconscious_eating`, `emotional_overeating`,
  `overconsumption`, `expectations_assessment`, `reason_justification`,
  `observations`, `notes`, and nested `recall_24h` (`breakfast`, `mid_morning`,
  `lunch`, `afternoon`, `dinner`, `vegetable_intake`, `fruit_intake`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Professionals.Anthropometrics

  schema "client_intakes" do
    field :assessed_on, :date
    field :height_m, :float
    field :weight_kg, :float
    field :bmi, :float
    field :usual_weight_kg, :float
    field :ideal_weight_kg, :float
    field :adjusted_weight_kg, :float
    field :bmr_kcal, :integer
    field :tdee_kcal, :integer
    field :sex, :string
    field :age, :integer
    field :activity_level, :string
    field :goal, :string
    field :details, :map, default: %{}

    belongs_to :professional_client, Mehungry.Professionals.ProfessionalClient

    timestamps()
  end

  def changeset(intake, attrs) do
    intake
    |> cast(attrs, [
      :professional_client_id,
      :assessed_on,
      :height_m,
      :weight_kg,
      :bmi,
      :usual_weight_kg,
      :ideal_weight_kg,
      :adjusted_weight_kg,
      :bmr_kcal,
      :tdee_kcal,
      :sex,
      :age,
      :activity_level,
      :goal,
      :details
    ])
    |> validate_required([:professional_client_id])
    |> validate_inclusion(:sex, Anthropometrics.sex_values())
    |> validate_inclusion(:activity_level, Anthropometrics.activity_values())
    |> validate_number(:age, greater_than: 0, less_than: 130)
    |> maybe_fill_energy()
    |> foreign_key_constraint(:professional_client_id)
  end

  # Fill BMI / BMR / TDEE from the raw inputs, but ONLY where the field is blank —
  # never overwrite a value the nutritionist typed (the live editor handles the
  # "recompute as inputs change" case). Uniform safety-net for CSV import, the API,
  # and first save.
  defp maybe_fill_energy(changeset) do
    derived =
      Anthropometrics.compute(%{
        height_m: get_field(changeset, :height_m),
        weight_kg: get_field(changeset, :weight_kg),
        sex: get_field(changeset, :sex),
        age: get_field(changeset, :age),
        activity_level: get_field(changeset, :activity_level)
      })

    Enum.reduce([:bmi, :bmr_kcal, :tdee_kcal], changeset, fn field, acc ->
      case {get_field(acc, field), Map.get(derived, field)} do
        {nil, value} when not is_nil(value) -> put_change(acc, field, value)
        _ -> acc
      end
    end)
  end
end
