defmodule Mehungry.MealBlueprints.Blueprint do
  @moduledoc """
  A reusable, user-owned "7-day meal-plan blueprint": a structured targets
  document (7 days × the calendar's meal slots) the user authors by hand. It
  carries no recipes — it is the *aim*, not the plan. A later phase lets the AI
  planner generate an actual calendar week that honours these targets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.MealBlueprints.BlueprintDay

  schema "meal_blueprints" do
    field(:name, :string)
    field(:description, :string)
    # "private" (owner-only) or "public" (browsable + shareable by slug).
    field(:visibility, :string, default: "private")
    # URL slug for the public preview page; generated once from the name.
    field(:slug, :string)
    # Blueprint-level "general" targets (apply across every day): nutrient +
    # bioactive-compound names sourced from the DB via the picker (required +
    # avoid), plus free-text preferred foods.
    field(:required_nutrients, {:array, :string}, default: [])
    field(:avoid_nutrients, {:array, :string}, default: [])
    # Per-nutrient threshold *value* keyed by nutrient name, interpreted by the
    # companion `*_nutrient_modes` map. In "pct" mode (the default) the value is a
    # 0..100 % of the day's calories (required = floor ≥, avoid = ceiling ≤). In
    # "amount" mode the value is a per-day total in the nutrient's own unit (e.g.
    # %{"Sodium" => 2300} ⇒ ≤ 2300 mg/day). Names without an entry fall back to
    # `@default_nutrient_pct` (pct mode). Keyed by the names in the matching
    # `*_nutrients` array; stale keys are pruned on save.
    field(:required_nutrient_pcts, :map, default: %{})
    field(:avoid_nutrient_pcts, :map, default: %{})
    # Per-nutrient threshold mode keyed by name: "pct" | "amount" (missing = "pct").
    field(:required_nutrient_modes, :map, default: %{})
    field(:avoid_nutrient_modes, :map, default: %{})
    field(:required_compounds, {:array, :string}, default: [])
    field(:avoid_compounds, {:array, :string}, default: [])
    field(:preferred_foods, {:array, :string}, default: [])
    # Free-text list of foods to exclude (the defining lever for avoidance diets
    # like Low-FODMAP); mirrors `preferred_foods`.
    field(:avoid_foods, {:array, :string}, default: [])

    # Populated by list queries for card display; not persisted.
    field(:plans_count, :integer, virtual: true)

    belongs_to(:user, Mehungry.Accounts.User)
    # Optional disease scoping the whole blueprint (e.g. "Ulcerative Colitis");
    # applies across all days/meals and seeds the compound suggestions above.
    belongs_to(:condition, Mehungry.Health.Condition)

    has_many(:plans, Mehungry.MealBlueprints.BlueprintPlan)

    has_many(:days, BlueprintDay,
      foreign_key: :blueprint_id,
      preload_order: [asc: :day_index],
      on_replace: :delete
    )

    timestamps()
  end

  @tag_fields [
    :required_nutrients,
    :avoid_nutrients,
    :required_compounds,
    :avoid_compounds,
    :preferred_foods,
    :avoid_foods
  ]

  # Each per-nutrient {value map, mode map, name array} triple.
  @nutrient_target_fields [
    {:required_nutrient_pcts, :required_nutrient_modes, :required_nutrients},
    {:avoid_nutrient_pcts, :avoid_nutrient_modes, :avoid_nutrients}
  ]

  # Caloric-% threshold assumed for a listed nutrient that has no explicit entry
  # in its pct map (keeps pre-existing blueprints and presets working without a
  # data backfill). A flat 10% only suits the energy macros (protein/carbs/fat);
  # see `default_nutrient_pct/1`.
  @default_nutrient_pct 10

  @doc "Default caloric-% threshold for a macro (or unknown) nutrient."
  def default_nutrient_pct, do: @default_nutrient_pct

  @doc """
  Default caloric-% threshold for a *named* listed nutrient with no explicit pct.

  A flat 10%-of-calories floor only makes sense for the three energy macros. An
  energy-dense trace fat like Omega-3 contributes only a fraction of a percent of
  the day's calories even at a generous intake (≈1.6 g × 9 kcal/g ≈ 0.7% of a
  2000 kcal day), so a 10% floor is physiologically unreachable and the goal
  could never read as met. These per-nutrient floors are realistic caloric shares
  at recommended intakes, mirroring the categories in
  `PlanCompatibility.nutrient_kcal_factor/1`. Zero-calorie micronutrients
  (vitamins/minerals) have no caloric share, so pct mode cannot represent a
  meaningful floor for them — author those as amount-mode goals instead.
  """
  def default_nutrient_pct(name) do
    n = name |> to_string() |> String.downcase()

    cond do
      String.contains?(n, "omega-3") -> 0.5
      String.contains?(n, "omega-6") -> 2
      String.contains?(n, "omega-9") -> 1
      String.contains?(n, "omega") -> 1
      String.contains?(n, "pufa") -> 5
      String.contains?(n, "mufa") -> 5
      String.contains?(n, "fiber") or String.contains?(n, "fibre") -> 2
      true -> @default_nutrient_pct
    end
  end

  @doc """
  Default threshold *mode* for a listed nutrient with no explicit mode: `"pct"`
  (caloric share) or `"amount"` (a per-day total in the nutrient's own unit).

  Fiber defaults to amount mode: its caloric share is intrinsically tiny (even the
  ≈25–38 g/day recommendation is only ~2–3% of calories), so a % reads as
  unresponsive — grams/day is how fiber is actually prescribed and lets the goal
  visibly track intake. Everything else stays in pct mode.
  """
  def default_nutrient_mode(name) do
    n = name |> to_string() |> String.downcase()
    if String.contains?(n, "fiber") or String.contains?(n, "fibre"), do: "amount", else: "pct"
  end

  @doc """
  Default per-day **amount** target (in the nutrient's own unit) for a nutrient
  that defaults to amount mode. 0 for nutrients that default to pct mode (their
  amount target is only used if the user explicitly switches them to amount).
  """
  def default_nutrient_amount(name) do
    n = name |> to_string() |> String.downcase()
    # Dietary Reference Intake floor for total fiber (~25 g/day, 2000 kcal diet).
    if String.contains?(n, "fiber") or String.contains?(n, "fibre"), do: 25, else: 0
  end

  @doc false
  def changeset(blueprint, attrs) do
    blueprint
    |> cast(attrs, [
      :name,
      :description,
      :user_id,
      :condition_id,
      :visibility,
      :required_nutrient_pcts,
      :avoid_nutrient_pcts,
      :required_nutrient_modes,
      :avoid_nutrient_modes | @tag_fields
    ])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:visibility, ~w(private public))
    |> clean_tags(@tag_fields)
    |> clean_nutrient_targets(@nutrient_target_fields)
    |> maybe_put_slug()
    |> cast_assoc(:days, with: &BlueprintDay.changeset/2)
    |> validate_day_count()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint(:slug)
  end

  # Generate a URL-safe slug from the name the first time one is needed, with a
  # short random suffix so distinct blueprints (including "Copy of …") never
  # collide; keep an existing slug stable across edits.
  defp maybe_put_slug(changeset) do
    existing = get_field(changeset, :slug)
    name = get_field(changeset, :name)

    cond do
      is_binary(existing) and existing != "" -> changeset
      is_nil(name) -> changeset
      true -> put_change(changeset, :slug, "#{slugify(name)}-#{random_suffix()}")
    end
  end

  @doc "Slugify a string into a URL-safe slug (lowercase, hyphenated, ascii)."
  def slugify(nil), do: "blueprint"

  def slugify(string) do
    slug =
      string
      |> String.downcase()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.trim()
      |> String.replace(~r/[\s-]+/, "-")

    if slug == "", do: "blueprint", else: slug
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false) |> String.downcase()
  end

  # Trim whitespace and drop blank/duplicate tags on each array field; leave a
  # missing value untouched.
  defp clean_tags(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      case get_change(acc, field) do
        nil ->
          acc

        tags ->
          cleaned = tags |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
          put_change(acc, field, cleaned)
      end
    end)
  end

  # Normalize each per-nutrient {value, mode} pair, keyed by the matching name
  # array (stale keys pruned so removing a nutrient drops its threshold). Modes are
  # limited to "pct"/"amount". Values are coerced to numbers and range-checked by
  # mode: pct values are 0..100 (fractional allowed, so a trace fat like Omega-3
  # can target a sub-1% caloric share); amount values are any non-negative number
  # (in the nutrient's own unit).
  defp clean_nutrient_targets(changeset, fields) do
    Enum.reduce(fields, changeset, fn {value_field, mode_field, name_field}, acc ->
      allowed = MapSet.new(get_field(acc, name_field) || [])

      modes =
        (get_field(acc, mode_field) || %{})
        |> Enum.filter(fn {name, mode} ->
          MapSet.member?(allowed, name) and mode in ["pct", "amount"]
        end)
        |> Map.new()

      raw_values = get_field(acc, value_field) || %{}

      {values, invalid} =
        Enum.reduce(raw_values, {%{}, false}, fn {name, value}, {map, bad} ->
          cond do
            not MapSet.member?(allowed, name) ->
              {map, bad}

            true ->
              mode = Map.get(modes, name, "pct")

              case coerce_value(value, mode) do
                {:ok, v} -> {Map.put(map, name, v), bad}
                :error -> {map, true}
              end
          end
        end)

      acc =
        acc
        |> put_change(mode_field, modes)
        |> put_change(value_field, values)

      if invalid,
        do:
          add_error(
            acc,
            value_field,
            "percentages must be between 0 and 100; amounts must be 0 or more"
          ),
        else: acc
    end)
  end

  # pct mode → 0..100 integer; amount mode → any non-negative number.
  defp coerce_value(value, "amount") do
    case coerce_number(value) do
      {:ok, n} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp coerce_value(value, _pct) do
    case coerce_number(value) do
      {:ok, n} when n >= 0 and n <= 100 -> {:ok, n}
      _ -> :error
    end
  end

  defp coerce_number(value) when is_integer(value), do: {:ok, value}
  defp coerce_number(value) when is_float(value), do: {:ok, value}

  defp coerce_number(value) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> {:ok, normalize_number(f)}
      :error -> :error
    end
  end

  defp coerce_number(_), do: :error

  # Keep whole numbers as integers (2300.0 → 2300) for tidy display/storage.
  defp normalize_number(f) do
    truncated = trunc(f)
    if truncated == f, do: truncated, else: f
  end

  # The skeleton builder always supplies exactly 7 distinct days (1..7); this
  # guards against a caller submitting a malformed tree.
  defp validate_day_count(changeset) do
    days = get_field(changeset, :days) || []
    indexes = days |> Enum.map(& &1.day_index) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if length(days) == 7 and length(indexes) == 7 do
      changeset
    else
      add_error(changeset, :days, "a blueprint must have exactly 7 distinct days")
    end
  end
end
