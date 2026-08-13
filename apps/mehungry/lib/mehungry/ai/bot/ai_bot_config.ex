defmodule Mehungry.AI.Bot.AiBotConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @meal_types ~w(breakfast morning_snack lunch afternoon_snack dinner)
  @setup_types ~w(theme condition)

  # Default publish time per meal (local "HH:MM"), applied to every language
  # unless the admin overrides it. Ordered breakfast → dinner.
  @default_publish_times %{
    "breakfast" => "06:00",
    "morning_snack" => "08:30",
    "lunch" => "11:00",
    "afternoon_snack" => "13:00",
    "dinner" => "15:30"
  }

  schema "ai_bot_configs" do
    field :theme, :string
    field :month, :integer
    field :year, :integer
    field :active, :boolean, default: true
    # "theme" — Month → Week → Day themes; "condition" — disease-driven setup
    field :setup_type, :string, default: "theme"
    # Free-text dietary direction for condition setup, e.g. "Mediterranean diet"
    field :diet_direction, :string
    field :pinterest_default_board_id, :string
    field :facebook_page_id, :string
    # JSONB map: %{"breakfast" => %{"en" => "07:00:00", "el" => "08:00:00"}, ...}
    field :publish_times, :map, default: %{}
    # Per-language targets: %{"en" => "page_id", "el" => "page_id"}
    field :facebook_page_ids, :map, default: %{}
    # Per-language Pinterest boards: %{"en" => "board_id", "el" => "board_id"}
    field :pinterest_board_ids, :map, default: %{}

    belongs_to :bot_user, Mehungry.Accounts.User
    belongs_to :condition, Mehungry.Health.Condition
    belongs_to :recipe_setup, Mehungry.AI.Bot.RecipeSetup
    has_many :ai_bot_recipes, Mehungry.AI.Bot.AiBotRecipe, foreign_key: :bot_config_id
    has_many :week_configs, Mehungry.AI.Bot.WeekConfig, foreign_key: :bot_config_id
    has_many :day_configs, Mehungry.AI.Bot.DayConfig, foreign_key: :bot_config_id

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :theme,
      :month,
      :year,
      :bot_user_id,
      :active,
      :setup_type,
      :condition_id,
      :diet_direction,
      :recipe_setup_id,
      :pinterest_default_board_id,
      :facebook_page_id,
      :publish_times,
      :facebook_page_ids,
      :pinterest_board_ids
    ])
    |> validate_required([:month, :year, :bot_user_id])
    |> validate_inclusion(:setup_type, @setup_types)
    |> validate_inclusion(:month, 1..12)
    |> validate_number(:year, greater_than: 2020)
    |> validate_setup_fields()
    |> normalize_publish_times()
    |> unique_constraint([:month, :year])
    |> foreign_key_constraint(:bot_user_id)
    |> foreign_key_constraint(:condition_id)
    |> foreign_key_constraint(:recipe_setup_id)
  end

  # Coerce every submitted time to "HH:MM:SS" (the format the publish worker
  # parses with `Time.from_iso8601/1`) and drop blank entries. A `<input
  # type="time">` submits "HH:MM", so without this the worker would fail to
  # schedule any publish job.
  defp normalize_publish_times(changeset) do
    case fetch_change(changeset, :publish_times) do
      {:ok, times} when is_map(times) ->
        put_change(changeset, :publish_times, normalize_times_map(times))

      _ ->
        changeset
    end
  end

  defp normalize_times_map(times) do
    Map.new(times, fn {meal, langs} ->
      normalized =
        langs
        |> Enum.map(fn {lang, t} -> {lang, normalize_time(t)} end)
        |> Enum.reject(fn {_lang, t} -> is_nil(t) end)
        |> Map.new()

      {meal, normalized}
    end)
  end

  defp normalize_time(t) when is_binary(t) do
    case t |> String.trim() |> String.split(":") do
      [""] -> nil
      [h, m] -> "#{pad2(h)}:#{pad2(m)}:00"
      [h, m, s] -> "#{pad2(h)}:#{pad2(m)}:#{pad2(s)}"
      _ -> nil
    end
  end

  defp normalize_time(_), do: nil

  defp pad2(s), do: String.pad_leading(s, 2, "0")

  # A theme setup needs a `theme`; a condition setup needs a `condition_id`
  # (the encouraged/discouraged ingredients are derived from it) and a
  # `diet_direction` (the general steer, e.g. "Mediterranean diet").
  defp validate_setup_fields(changeset) do
    case get_field(changeset, :setup_type) do
      "condition" -> validate_required(changeset, [:condition_id, :diet_direction])
      _ -> validate_required(changeset, [:theme])
    end
  end

  def meal_types, do: @meal_types
  def setup_types, do: @setup_types
  def default_publish_times, do: @default_publish_times
  def default_time_for(meal_type), do: Map.get(@default_publish_times, meal_type)
end
