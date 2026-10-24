defmodule MehungryWeb.MealTypeLabels do
  @moduledoc """
  Localized **display** labels for meal-type slots (Breakfast, Morning Snack, …).

  The canonical English labels are the domain vocabulary in
  `Mehungry.History.MealType.label/1`; this web-side gate translates them via
  Gettext, mirroring `MehungryWeb.NutrientLabels` (display text is translated in
  the web layer, never in the core domain). One `gettext/1` clause is generated
  per canonical label so `mix gettext.extract` discovers them; anything unknown
  passes through unchanged.

  Use `label/1` from inside a request / LiveView process (it uses the locale set
  by `SetLocale`/`RestoreLocale`). Use `label/2` with an explicit locale from code
  that runs *outside* that process — e.g. the weekly-plan share card, which renders
  in an async `Task` where the process locale isn't set.
  """
  use Gettext, backend: MehungryWeb.Gettext

  alias Mehungry.History.MealType

  @doc "Localized label for a meal-type value, using the current process locale."
  def label(meal_type), do: translate(MealType.label(meal_type))

  @doc "Localized label for a meal-type value under an explicit `locale`."
  def label(meal_type, locale) when locale in [nil, "en", "En"], do: MealType.label(meal_type)

  def label(meal_type, locale),
    do: Gettext.with_locale(locale, fn -> translate(MealType.label(meal_type)) end)

  # One clause per canonical label (string literals so extraction can see them).
  for en <- Enum.uniq(Enum.map(MealType.values() ++ [nil], &MealType.label/1)) do
    def translate(unquote(en)), do: gettext(unquote(en))
  end

  def translate(other), do: other
end
