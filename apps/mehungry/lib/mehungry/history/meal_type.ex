defmodule Mehungry.History.MealType do
  @moduledoc """
  Single source of truth for the meal-planner meal-type vocabulary and its
  human labels. `UserMeal.meal_type` is validated against `values/0`; the
  calendar groups a day's meals by these values (with `nil` shown last as
  "Unsorted"). Mirrors the AI bot's `AiBotConfig.meal_types/0` vocabulary —
  a test guards against the two drifting apart.
  """

  # Storage order == display order; callers append `nil` (unsorted) last.
  @values ~w(breakfast morning_snack lunch afternoon_snack dinner)

  @doc "The canonical meal-type values, in display order."
  def values, do: @values

  @doc "Alias for `values/0`; the ordered list callers iterate for display."
  def ordered, do: @values

  @doc "True for a known value or `nil` (the unsorted bucket)."
  def valid?(nil), do: true
  def valid?(value), do: value in @values

  @doc "Human label for a value; `nil`/unknown → \"Unsorted\"."
  def label("breakfast"), do: "Breakfast"
  def label("morning_snack"), do: "Morning Snack"
  def label("lunch"), do: "Lunch"
  def label("afternoon_snack"), do: "Afternoon Snack"
  def label("dinner"), do: "Dinner"
  def label(_other), do: "Unsorted"

  @doc """
  Maps an AI meal-plan slot string (the labels emitted by `label/1`, e.g.
  "Breakfast", "Morning Snack", "Dinner") to a canonical value; anything else →
  `nil` (unsorted).
  """
  def from_slot("Breakfast"), do: "breakfast"
  def from_slot("Morning Snack"), do: "morning_snack"
  def from_slot("Lunch"), do: "lunch"
  def from_slot("Afternoon Snack"), do: "afternoon_snack"
  def from_slot("Dinner"), do: "dinner"
  def from_slot(_other), do: nil

  @doc """
  Default time-of-day for a canonical meal-type value, used when materializing a
  planned meal onto a calendar date. Unknown/nil → noon.
  """
  def slot_time("breakfast"), do: ~T[08:00:00]
  def slot_time("morning_snack"), do: ~T[10:30:00]
  def slot_time("lunch"), do: ~T[13:00:00]
  def slot_time("afternoon_snack"), do: ~T[16:30:00]
  def slot_time("dinner"), do: ~T[19:00:00]
  def slot_time(_other), do: ~T[12:00:00]
end
