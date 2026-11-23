defmodule Mehungry.Professionals.CalorieBand do
  @moduledoc """
  The daily calorie **range** a meal plan for a client must land in — the single
  definition read by the AI draft's validator, the agent's brief, and the client
  file's Energy card.

  Pure (no DB). Precedence:

    1. an explicit `target_kcal` the nutritionist prescribed → ±10% of it
       (the goal type is ignored — a typed target already *is* the deficit/surplus);
    2. else the estimated `tdee_kcal`, shifted by the goal type:
       `lose` −20%…−10% · `maintain` (or unset) −10%…+10% · `gain` +10%…+20%;
    3. else the client's own self-set target → ±10%;
    4. else `nil` — no target, nothing to check.

  `aim` is the point the planner steers at (the middle of the range).
  """

  @goal_types [{"lose", "Lose weight"}, {"maintain", "Maintain weight"}, {"gain", "Gain weight"}]

  # {min factor, max factor, aim factor, basis} applied to TDEE. The basis atoms
  # are literals here (never built with String.to_existing_atom/1: in a lazily
  # loading node — `bin/… eval` — nothing else may have created them yet).
  @goal_factors %{
    "lose" => {0.80, 0.90, 0.85, :goal_lose},
    "maintain" => {0.90, 1.10, 1.0, :goal_maintain},
    "gain" => {1.10, 1.20, 1.15, :goal_gain}
  }

  @tolerance 0.10

  @type t :: %{
          min: integer,
          max: integer,
          aim: integer,
          basis: :prescribed | :goal_lose | :goal_maintain | :goal_gain | :self
        }

  @doc "Allowed `goal_type` values with English labels, for the picker and validation."
  def goal_types, do: @goal_types

  @doc "Valid `goal_type` string values."
  def goal_type_values, do: Enum.map(@goal_types, &elem(&1, 0))

  @doc "English label for a stored `goal_type` (`nil` → `nil`)."
  def goal_type_label(goal_type) do
    Enum.find_value(@goal_types, fn {value, label} -> if value == goal_type, do: label end)
  end

  @doc """
  The band for an intake-like map (`target_kcal`, `tdee_kcal`, `goal_type` — any
  may be missing; `nil` intake allowed) and the client's own self-set target.
  """
  @spec band(map | nil, integer | nil) :: t | nil
  def band(intake, own_target \\ nil) do
    target = field(intake, :target_kcal)
    tdee = field(intake, :tdee_kcal)

    cond do
      positive?(target) -> around(target, :prescribed)
      positive?(tdee) -> from_goal(tdee, field(intake, :goal_type))
      positive?(own_target) -> around(own_target, :self)
      true -> nil
    end
  end

  @doc "A ±10% band around a plain target (e.g. a user's own, or a blueprint day's)."
  @spec around(number, atom) :: t
  def around(target, basis \\ :self) do
    %{
      min: round(target * (1 - @tolerance)),
      max: round(target * (1 + @tolerance)),
      aim: round(target),
      basis: basis
    }
  end

  defp from_goal(tdee, goal_type) do
    goal = if Map.has_key?(@goal_factors, goal_type), do: goal_type, else: "maintain"
    {lo, hi, aim, basis} = Map.fetch!(@goal_factors, goal)

    %{
      min: round(tdee * lo),
      max: round(tdee * hi),
      aim: round(tdee * aim),
      basis: basis
    }
  end

  defp field(nil, _key), do: nil
  defp field(map, key), do: Map.get(map, key)

  defp positive?(n), do: is_number(n) and n > 0
end
