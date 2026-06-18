defmodule Mehungry.AiBot do
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Posts
  alias Mehungry.AiBot.{AiBotConfig, AiBotRecipe, RecipeTranslation, SocialMediaPostLog, WeekConfig, DayConfig}

  # ── Config ──────────────────────────────────────────────────────────────────

  def list_bot_configs do
    AiBotConfig
    |> order_by([c], [desc: c.year, desc: c.month])
    |> preload(:bot_user)
    |> Repo.all()
  end

  def get_bot_config!(id), do: Repo.get!(AiBotConfig, id) |> Repo.preload(:bot_user)

  def get_active_config_for_month(month, year) do
    AiBotConfig
    |> where([c], c.month == ^month and c.year == ^year and c.active == true)
    |> preload(:bot_user)
    |> Repo.one()
  end

  def create_bot_config(attrs \\ %{}) do
    %AiBotConfig{}
    |> AiBotConfig.changeset(attrs)
    |> Repo.insert()
  end

  def update_bot_config(%AiBotConfig{} = config, attrs) do
    config
    |> AiBotConfig.changeset(attrs)
    |> Repo.update()
  end

  def delete_bot_config(%AiBotConfig{} = config), do: Repo.delete(config)

  def change_bot_config(%AiBotConfig{} = config, attrs \\ %{}) do
    AiBotConfig.changeset(config, attrs)
  end

  # ── Bot Recipes ──────────────────────────────────────────────────────────────

  def list_pending_recipes do
    list_bot_recipes("pending_review")
  end

  def list_bot_recipes("all") do
    AiBotRecipe
    |> order_by([r], [asc: r.scheduled_date, asc: r.meal_type])
    |> preload([:recipe, :bot_config])
    |> Repo.all()
  end

  def list_bot_recipes(status) do
    AiBotRecipe
    |> where([r], r.status == ^status)
    |> order_by([r], [asc: r.scheduled_date, asc: r.meal_type])
    |> preload([:recipe, :bot_config])
    |> Repo.all()
  end

  def count_pending_reviews do
    AiBotRecipe
    |> where([r], r.status == "pending_review")
    |> Repo.aggregate(:count)
  end

  def list_recipes_for_date(date) do
    AiBotRecipe
    |> where([r], r.scheduled_date == ^date)
    |> order_by([r], r.meal_type)
    |> preload([:recipe, :bot_config, :social_media_post_logs])
    |> Repo.all()
  end

  def get_bot_recipe!(id) do
    AiBotRecipe
    |> Repo.get!(id)
    |> Repo.preload([:bot_config, recipe: [recipe_ingredients: [:ingredient, :measurement_unit], recipe_hashtags: []]])
  end

  def list_untracked_bot_recipes(bot_user_id) do
    tracked_ids =
      AiBotRecipe
      |> select([r], r.recipe_id)
      |> Repo.all()

    Mehungry.Food.Recipe
    |> where([r], r.user_id == ^bot_user_id and r.id not in ^tracked_ids)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
  end

  def import_single_recipe(recipe_id, %AiBotConfig{} = config, scheduled_date) do
    meal_types = AiBotConfig.meal_types()

    existing_meal_types =
      AiBotRecipe
      |> where([r], r.bot_config_id == ^config.id and r.scheduled_date == ^scheduled_date)
      |> select([r], r.meal_type)
      |> Repo.all()

    meal_type =
      Enum.find(meal_types, "lunch", fn mt -> mt not in existing_meal_types end)

    create_bot_recipe(%{
      recipe_id: recipe_id,
      bot_config_id: config.id,
      meal_type: meal_type,
      scheduled_date: scheduled_date,
      status: "pending_review"
    })
  end

  def dismiss_untracked_recipe(recipe_id, %AiBotConfig{} = config) do
    create_bot_recipe(%{
      recipe_id: recipe_id,
      bot_config_id: config.id,
      meal_type: "lunch",
      scheduled_date: Date.utc_today(),
      status: "rejected"
    })
  end

  def bot_recipe_exists?(bot_config_id, meal_type, scheduled_date) do
    AiBotRecipe
    |> where([r], r.bot_config_id == ^bot_config_id and r.meal_type == ^meal_type and r.scheduled_date == ^scheduled_date)
    |> Repo.exists?()
  end

  def create_bot_recipe(attrs \\ %{}) do
    %AiBotRecipe{}
    |> AiBotRecipe.changeset(attrs)
    |> Repo.insert()
  end

  def approve_recipe(%AiBotRecipe{} = bot_recipe) do
    with {:ok, updated} <-
           bot_recipe
           |> AiBotRecipe.changeset(%{status: "approved"})
           |> Repo.update() do
      recipe = Repo.get!(Mehungry.Food.Recipe, bot_recipe.recipe_id)
      ensure_posts_for_recipe(recipe)
      {:ok, updated}
    end
  end

  defp ensure_posts_for_recipe(recipe) do
    unless Posts.post_exists_for?(recipe.id, nil) do
      Posts.create_post(recipe)
    end

    recipe.id
    |> list_translations_for_recipe()
    |> Enum.each(fn translation ->
      unless Posts.post_exists_for?(recipe.id, translation.language_name) do
        Posts.create_post_for_translation(recipe, translation)
      end
    end)
  end

  def reject_recipe(%AiBotRecipe{} = bot_recipe) do
    bot_recipe
    |> AiBotRecipe.changeset(%{status: "rejected"})
    |> Repo.update()
  end

  def mark_published(%AiBotRecipe{} = bot_recipe) do
    bot_recipe
    |> AiBotRecipe.changeset(%{status: "published"})
    |> Repo.update()
  end

  # ── Week Configs ─────────────────────────────────────────────────────────────

  def week_number_of_month(%Date{day: day}), do: div(day - 1, 7) + 1

  def list_week_configs(bot_config_id) do
    WeekConfig
    |> where([w], w.bot_config_id == ^bot_config_id)
    |> order_by([w], w.week_number)
    |> Repo.all()
  end

  def get_week_config(bot_config_id, week_number) do
    WeekConfig
    |> where([w], w.bot_config_id == ^bot_config_id and w.week_number == ^week_number)
    |> Repo.one()
  end

  def upsert_week_config(attrs) do
    bot_config_id = attrs[:bot_config_id] || attrs["bot_config_id"]
    week_number = attrs[:week_number] || attrs["week_number"]
    existing = get_week_config(bot_config_id, week_number)

    case existing do
      nil ->
        %WeekConfig{}
        |> WeekConfig.changeset(attrs)
        |> Repo.insert()

      wc ->
        wc
        |> WeekConfig.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_week_config(%WeekConfig{} = wc), do: Repo.delete(wc)

  # ── Day Configs ───────────────────────────────────────────────────────────────

  def list_day_configs(bot_config_id) do
    DayConfig
    |> where([d], d.bot_config_id == ^bot_config_id)
    |> order_by([d], d.date)
    |> Repo.all()
  end

  def get_day_config(bot_config_id, date) do
    DayConfig
    |> where([d], d.bot_config_id == ^bot_config_id and d.date == ^date)
    |> Repo.one()
  end

  def upsert_day_config(attrs) do
    bot_config_id = attrs[:bot_config_id] || attrs["bot_config_id"]
    date = attrs[:date] || attrs["date"]
    existing = get_day_config(bot_config_id, date)

    case existing do
      nil ->
        %DayConfig{}
        |> DayConfig.changeset(attrs)
        |> Repo.insert()

      dc ->
        dc
        |> DayConfig.changeset(attrs)
        |> Repo.update()
    end
  end

  def delete_day_config(%DayConfig{} = dc), do: Repo.delete(dc)

  def get_context_for_date(%AiBotConfig{} = config, date) do
    week_num = week_number_of_month(date)
    week = get_week_config(config.id, week_num)
    day = get_day_config(config.id, date)

    %{
      month_theme: config.theme,
      week_theme: week && week.theme,
      day_focus: day && day.focus_hint
    }
  end

  # ── Translations ─────────────────────────────────────────────────────────────

  def get_recipe_translation(recipe_id, language_name) do
    RecipeTranslation
    |> where([t], t.recipe_id == ^recipe_id and t.language_name == ^language_name)
    |> Repo.one()
  end

  def list_translations_for_recipe(recipe_id) do
    RecipeTranslation
    |> where([t], t.recipe_id == ^recipe_id)
    |> Repo.all()
  end

  def upsert_recipe_translation(attrs) do
    existing = get_recipe_translation(attrs[:recipe_id] || attrs["recipe_id"], attrs[:language_name] || attrs["language_name"])

    case existing do
      nil ->
        %RecipeTranslation{}
        |> RecipeTranslation.changeset(attrs)
        |> Repo.insert()

      translation ->
        translation
        |> RecipeTranslation.changeset(attrs)
        |> Repo.update()
    end
  end

  def change_recipe_translation(%RecipeTranslation{} = translation, attrs \\ %{}) do
    RecipeTranslation.changeset(translation, attrs)
  end

  # ── Post Logs ────────────────────────────────────────────────────────────────

  def create_post_log(attrs \\ %{}) do
    %SocialMediaPostLog{}
    |> SocialMediaPostLog.changeset(attrs)
    |> Repo.insert()
  end

  def list_post_logs_for_bot_recipe(ai_bot_recipe_id) do
    SocialMediaPostLog
    |> where([l], l.ai_bot_recipe_id == ^ai_bot_recipe_id)
    |> order_by([l], l.inserted_at)
    |> Repo.all()
  end

  def all_languages_published?(ai_bot_recipe_id, languages) do
    logged_langs =
      SocialMediaPostLog
      |> where([l], l.ai_bot_recipe_id == ^ai_bot_recipe_id and l.status in ["ok", "skipped"])
      |> select([l], l.language_name)
      |> Repo.all()

    Enum.all?(languages, &(&1 in logged_langs))
  end
end
