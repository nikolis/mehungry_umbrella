defmodule Mehungry.Food.MealRoles do
  @moduledoc """
  The fixed vocabulary of **meal roles** — what part a recipe plays in a real
  meal (a main, a side, a meze, a breakfast…). Single source of truth: the
  `recipe_meal_roles` rows are validated against `all/0`, the AI classifier is
  prompted with `description/1`, and the meal planner decides which recipes may
  fill which calendar slot through `slot_roles/1` / `fits_slot?/2`.

  A recipe may carry **several** roles (spanakopita is a `main`, a `side`, a
  `meze` and a `snack`). The list is deliberately fixed in code — not admin
  editable — because the planner's logic keys on specific roles (`main`,
  `soup`); see `docs/implementation/food/meal_roles.md`.
  """

  @roles [
    {"breakfast", "Breakfast",
     "A breakfast dish (eggs, porridge, pancakes, yogurt bowls, toast)."},
    {"main", "Main",
     "A main course that is a complete lunch or dinner on its own — has substance and usually a protein source."},
    {"soup", "Soup",
     "A soup or stew-like soup that can be the whole meal (fasolada, avgolemono, lentil soup)."},
    {"salad", "Salad", "A salad, eaten alongside a meal (or a light meal only if very hearty)."},
    {"side", "Side",
     "A side dish that accompanies a main (rice, roasted vegetables, potatoes, greens)."},
    {"meze", "Meze",
     "A meze / appetizer / dip / shared small plate (tzatziki, baba ganoush, patlıcan salatası, dolmades)."},
    {"snack", "Snack", "A small between-meal snack."},
    {"dessert", "Dessert", "A dessert or sweet (cakes, cookies, sweet pastries, puddings)."},
    {"drink", "Drink", "A drink or smoothie."},
    {"component", "Component",
     "A building block, not eaten on its own: sauce, dressing, dough, stock, spice mix, marinade."}
  ]

  @all Enum.map(@roles, &elem(&1, 0))

  # Which roles may fill each calendar slot. Keys are the slot labels the
  # planner emits (`MealPlanCore.slots/0`) and the canonical MealType values.
  @breakfast ~w(breakfast)
  @meal ~w(main soup)
  @snack ~w(snack dessert drink)

  @slot_roles %{
    "Breakfast" => @breakfast,
    "breakfast" => @breakfast,
    "Lunch" => @meal,
    "lunch" => @meal,
    "Dinner" => @meal,
    "dinner" => @meal,
    "Morning Snack" => @snack,
    "morning_snack" => @snack,
    "Afternoon Snack" => @snack,
    "afternoon_snack" => @snack
  }

  @doc "Every role, in display order."
  def all, do: @all

  @doc "True when `role` is in the vocabulary."
  def valid?(role), do: role in @all

  @doc "Human label for a role."
  def label(role) do
    case List.keyfind(@roles, role, 0) do
      {_, label, _} -> label
      nil -> role
    end
  end

  @doc "One-sentence definition (also used to prompt the classifier)."
  def description(role) do
    case List.keyfind(@roles, role, 0) do
      {_, _, description} -> description
      nil -> ""
    end
  end

  @doc "Roles that make a complete lunch or dinner on their own."
  def meal_capable, do: @meal

  @doc """
  The roles a recipe needs (at least one of) to fill `slot` — a planner slot
  label ("Dinner") or a canonical meal type ("dinner"). Unknown slot → `[]`.
  """
  def slot_roles(slot), do: Map.get(@slot_roles, slot, [])

  @doc """
  Whether a recipe with `roles` may fill `slot`.

  `nil` / `[]` means **unclassified** and always fits, so the planner keeps
  working for recipes the classifier hasn't reached yet. An unknown slot fits
  anything (nothing to check against).
  """
  def fits_slot?(roles, _slot) when roles in [nil, []], do: true

  def fits_slot?(roles, slot) do
    case slot_roles(slot) do
      [] -> true
      accepted -> Enum.any?(roles, &(&1 in accepted))
    end
  end
end
