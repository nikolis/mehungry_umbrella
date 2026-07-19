# Contexts

## defmodule Mehungry.Users do

## defmodule Mehungry.AiBot do
  def list_bot_configs do
  def get_bot_config!(id), do: Repo.get!(AiBotConfig, id) |> Repo.preload(:bot_user)
  def get_active_config_for_month(month, year) do
  def create_bot_config(attrs \\ %{}) do
  def update_bot_config(%AiBotConfig{} = config, attrs) do
  def delete_bot_config(%AiBotConfig{} = config), do: Repo.delete(config)
  def change_bot_config(%AiBotConfig{} = config, attrs \\ %{}) do
  def list_pending_recipes do
  def list_bot_recipes("all") do
  def list_bot_recipes(status) do
  def count_pending_reviews do
  def list_recipes_for_date(date) do
  def get_bot_recipe!(id) do
  def list_untracked_bot_recipes(bot_user_id) do
  def import_single_recipe(recipe_id, %AiBotConfig{} = config, scheduled_date) do
  def dismiss_untracked_recipe(recipe_id, %AiBotConfig{} = config) do
  def bot_recipe_exists?(bot_config_id, meal_type, scheduled_date) do
  def create_bot_recipe(attrs \\ %{}) do
  def approve_recipe(%AiBotRecipe{} = bot_recipe) do
  def reject_recipe(%AiBotRecipe{} = bot_recipe) do
  def mark_published(%AiBotRecipe{} = bot_recipe) do
  def week_number_of_month(%Date{day: day}), do: div(day - 1, 7) + 1
  def list_week_configs(bot_config_id) do
  def get_week_config(bot_config_id, week_number) do
  def upsert_week_config(attrs) do
  def delete_week_config(%WeekConfig{} = wc), do: Repo.delete(wc)
  def list_day_configs(bot_config_id) do
  def get_day_config(bot_config_id, date) do
  def upsert_day_config(attrs) do
  def delete_day_config(%DayConfig{} = dc), do: Repo.delete(dc)
  def get_context_for_date(%AiBotConfig{} = config, date) do
  def get_recipe_translation(recipe_id, language_name) do
  def list_translations_for_recipe(recipe_id) do
  def upsert_recipe_translation(attrs) do
  def change_recipe_translation(%RecipeTranslation{} = translation, attrs \\ %{}) do
  def create_post_log(attrs \\ %{}) do
  def list_post_logs_for_bot_recipe(ai_bot_recipe_id) do
  def platforms_successfully_posted(ai_bot_recipe_id, language_name) do
  def all_languages_published?(ai_bot_recipe_id, languages) do

## defmodule Mehungry.SocialMediaPublisher do

## defmodule Mehungry.Accounts.UserIngredientRule do
  def changeset(user_ingredient_rule, attrs) do

## defmodule Mehungry.Accounts.UserNotifier do
  def deliver_confirmation_instructions(user, url) do
  def deliver_reset_password_instructions(user, url) do
  def deliver_update_email_instructions(user, url) do

## defmodule Mehungry.Accounts.UserCategoryRule do
  def changeset(user_category_rule, attrs) do

## defmodule Mehungry.Accounts.UserFollow do
  def changeset(user_follow, attrs) do

## defmodule Mehungry.Accounts.UserRecipe do
  def changeset(user_recipe, attrs) do

## defmodule Mehungry.Accounts.Auth do
  def get_user_by_email_and_password(email, password)
  def register_user(attrs) do
  def change_user_registration(%User{} = user, attrs \\ %{}) do
  def change_user_email(user, attrs \\ %{}) do
  def apply_user_email(user, password, attrs) do
  def update_user_email(user, token) do
  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
  def change_user_password(user, attrs \\ %{}) do
  def update_user_password(user, password, attrs) do
  def generate_user_session_token(user) do
  def get_user_by_session_token(token) do
  def delete_session_token(token) do
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
  def confirm_user(token) do
  def confirm_user_multi(user) do
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
  def get_user_by_reset_password_token(token) do
  def reset_user_password(user, attrs) do

## defmodule Mehungry.Accounts.Grading do
  def calculate_recipe_grading(nil, _user) do
  def calculate_recipe_grading(recipe, user) do
  def calculate_recipe_grading(nil, _user_pref_table, _follow_ids), do: 0
  def calculate_recipe_grading(recipe, user_pref_table, follow_ids) do
  def calculate_user_pref_table(user) do
  def get_category_name(category) do
  def get_user_category_rules(user) do
  def get_user_category_rulles(%User{} = user) do

## defmodule Mehungry.Accounts.Admin do
  def get_user_by_email(email) when is_binary(email) do
  def get_user_by_canonical_email(email) when is_binary(email) do
  def get_user!(id), do: Repo.get!(User, id)
  def list_users(filters \\ %{}) do
  def count_users do
  def dedupe_alias_accounts(opts \\ []) do
  def delete_user(%User{} = user) do

## defmodule Mehungry.Accounts.Profiles do
  def list_user_profiles do
  def get_user_profile!(id), do: Repo.get!(UserProfile, id)
  def get_user_profile_by_user_id(id) do
  def create_user_profile(attrs \\ %{}) do
  def create_user_profile_if_needed(user) do
  def update_user_profile(%UserProfile{} = user_profile, attrs) do
  def update_user_language(%UserProfile{} = profile, lang) when lang in ["en", "el"] do
  def get_user_language(user_id) do
  def delete_user_profile(%UserProfile{} = user_profile) do
  def change_user_profile(%UserProfile{} = user_profile, attrs \\ %{}) do
  def get_user_essentials(nil), do: {nil, [], []}
  def get_user_essentials(%User{} = user) do
  def count_user_following(nil), do: nil
  def count_user_following(user_id) do
  def count_user_followers(nil), do: nil
  def count_user_followers(user_id) do
  def count_user_saved_recipes(nil), do: nil
  def count_user_saved_recipes(user_id) do

## defmodule Mehungry.Accounts.Rules do
  def list_user_category_rules do
  def get_user_category_rule!(id), do: Repo.get!(UserCategoryRule, id)
  def create_user_category_rule(attrs \\ %{}) do
  def update_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs) do
  def delete_user_category_rule(%UserCategoryRule{} = user_category_rule) do
  def change_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs \\ %{}) do
  def list_user_ingredient_rules do
  def get_user_ingredient_rule!(id), do: Repo.get!(UserIngredientRule, id)
  def create_user_ingredient_rule(attrs \\ %{}) do
  def update_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs) do
  def delete_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule) do
  def change_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs \\ %{}) do

## defmodule Mehungry.Accounts.UserPost do
  def changeset(user_post, attrs) do

## defmodule Mehungry.Accounts.UserProfile do
  def changeset(user_profile, attrs) do

## defmodule Mehungry.Accounts.UserToken do
  def build_session_token(user) do
  def verify_session_token_query(token) do
  def build_email_token(user, context) do
  def verify_email_token_query(token, context) do
  def verify_change_email_token_query(token, "change:" <> _ = context) do
  def token_and_context_query(token, context) do
  def user_and_contexts_query(user, :all) do
  def user_and_contexts_query(user, [_ | _] = contexts) do

## defmodule Mehungry.Accounts.UserContent do
  def save_user_recipe(user_id, recipe_id) do
  def save_user_post(user_id, post_id) do
  def save_user_follow(user_id, follow_id) when is_integer(user_id) and is_integer(follow_id) do
  def remove_user_saved_recipe(user_id, recipe_id)
  def remove_user_saved_post(user_id, post_id)
  def remove_user_follow(user_id, follow_id)
  def list_user_saved_recipes(%User{} = user) do
  def list_user_saved_recipe_ids(%User{} = user) do
  def list_user_follows(%User{} = user) do
  def list_user_saved_posts(%User{} = user) do
  def list_user_created_recipes(%User{} = user) do
  def remove_recipe_from_users_list(%User{} = user, %Recipe{} = recipe) do
  def create_user_restriction_type(attrs) do

## defmodule Mehungry.Accounts.OAuth do
  def get_user_tokens(user, domain) do
  def put_user_token(user, token, domain) do
  def update_user(%User{} = user, attrs) do
  def update_user_tokens(%User{} = user, attrs) do
  def register_3rd_party_user(attrs) do
  def verify_3rd_party_user_changes(
  def verify_3rd_party_user_changes(%Auth{} = auth, %User{} = user) do
  def find_or_create(%Auth{} = auth) do
  def maybe_confirm_user(%User{confirmed_at: nil} = user) do
  def maybe_confirm_user(%User{} = user), do: user

## defmodule Mehungry.Accounts.User do
  def registration_changeset(user, attrs, opts \\ []) do
  def registration_3rd_party_changeset(user, attrs, _opts \\ []) do
  def tokens_changeset(user, attrs, _opts \\ []) do
  def canonical_email(email) when is_binary(email) do
  def email_changeset(user, attrs) do
  def password_changeset(user, attrs, opts \\ []) do
  def confirm_changeset(user) do
  def valid_password?(%Mehungry.Accounts.User{hashed_password: hashed_password}, password)
  def valid_password?(_, _) do
  def validate_current_password(changeset, password) do

## defmodule Mehungry.Posts.Post do
  def changeset(post, attrs) do

## defmodule Mehungry.Posts.Comment do
  def changeset(comment, attrs) do

## defmodule Mehungry.Posts.CommentAnswerVote do
  def changeset(comment_answer_vote, attrs) do

## defmodule Mehungry.Posts.PostDownvote do
  def changeset(post_downvote, attrs) do

## defmodule Mehungry.Posts.PostUpvote do
  def changeset(post_upvote, attrs) do

## defmodule Mehungry.Posts.CommentVote do
  def changeset(comment_vote, attrs) do

## defmodule Mehungry.Posts.CommentAnswer do
  def changeset(comment_answer, attrs) do

## defmodule Mehungry.Application do
  def start(_type, _args) do

## defmodule Mehungry.Plans do
  def list_meal_plans_for_user(user_id) do
  def list_meal_plans do
  def get_meal_plan!(id) do
  def create_meal_plan(attrs \\ %{}) do
  def update_meal_plan(%MealPlan{} = meal_plan, attrs) do
  def delete_meal_plan(%MealPlan{} = meal_plan) do
  def change_meal_plan(%MealPlan{} = meal_plan) do
  def list_daily_meal_plans do
  def get_daily_meal_plan!(id), do: Repo.get!(DailyMealPlan, id)
  def create_daily_meal_plan(attrs \\ %{}) do
  def update_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan, attrs) do
  def delete_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan) do
  def change_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan) do
  def list_meals do
  def get_meal!(id), do: Repo.get!(Meal, id)
  def create_meal(attrs \\ %{}) do
  def update_meal(%Meal{} = meal, attrs) do
  def delete_meal(%Meal{} = meal) do
  def change_meal(%Meal{} = meal) do

## defmodule Mehungry.Plans.MealPlan do
  def changeset(meal_plan, attrs) do

## defmodule Mehungry.Plans.DailyMealPlan do
  def changeset(daily_meal_plan, attrs) do

## defmodule Mehungry.Plans.Meal do
  def changeset(meal, attrs) do

## defmodule Mehungry.History do
  def list_history_user_meals do
  def get_available_portions_for_user_meal(recipe_user_meal_id) do
  def list_incomplete_user_meals2(user_id, _date_time) do
  def list_history_user_meals_for_user(user_id) do
  def list_history_user_meals_for_user(user_id, date) do
  def list_history_user_meals_for_user(user_id, start_dt, end_dt) do
  def get_user_meal!(id) do
  def get_user_meal_raw!(id) do
  def create_user_meal(attrs \\ %{}) do
  def update_user_meal(%UserMeal{} = user_meal, attrs) do
  def delete_user_meal(%UserMeal{} = user_meal) do
  def change_user_meal(%UserMeal{} = user_meal, attrs \\ %{}) do

## defmodule Mehungry.AiBot.DayConfig do
  def changeset(day_config, attrs) do

## defmodule Mehungry.AiBot.AiBotRecipe do
  def changeset(bot_recipe, attrs) do
  def valid_statuses, do: @valid_statuses
  def valid_meal_types, do: @valid_meal_types

## defmodule Mehungry.AiBot.WeekConfig do
  def changeset(week_config, attrs) do

## defmodule Mehungry.AiBot.AiBotConfig do
  def changeset(config, attrs) do
  def meal_types, do: @meal_types

## defmodule Mehungry.AiBot.Notifier do
  def deliver_recipes_ready(recipe_count, review_url) do

## defmodule Mehungry.AiBot.RecipeTranslation do
  def changeset(translation, attrs) do

## defmodule Mehungry.AiBot.SocialMediaPostLog do
  def changeset(log, attrs) do

## defmodule Mehungry.Mailer do

## defmodule Mehungry.Professionals do
  def get_professional_profile(user_id) do
  def get_professional_profile!(user_id) do
  def create_professional_profile(attrs) do
  def update_professional_profile(%ProfessionalProfile{} = profile, attrs) do
  def change_professional_profile(%ProfessionalProfile{} = profile, attrs \\ %{}) do
  def invite_client(professional_id, client_email, message \\ nil) do
  def get_invitation(id), do: Repo.get(TutorInvitation, id)
  def accept_invitation(invitation_id, client_id) do
  def decline_invitation(invitation_id, client_id) do
  def revoke_invitation(invitation_id, professional_id) do
  def list_pending_invitations_for_client(client_id) do
  def list_sent_invitations(professional_id) do
  def count_pending_invitations_for_client(client_id) do
  def list_clients(professional_id) do
  def count_clients(professional_id) do
  def get_assignment_for_client(client_id) do
  def get_assignment(professional_id, client_id) do
  def remove_client(professional_id, client_id) do
  def list_appointments_for_professional(professional_id, start_dt, end_dt) do
  def list_appointments_for_client(client_id) do
  def list_upcoming_appointments(professional_id, limit \\ 5) do
  def get_appointment!(id), do: Repo.get!(Appointment, id)
  def create_appointment(attrs) do
  def update_appointment(%Appointment{} = appointment, attrs) do
  def delete_appointment(%Appointment{} = appointment) do
  def change_appointment(%Appointment{} = appointment, attrs \\ %{}) do
  def upsert_meal_plan_rating(attrs) do
  def get_rating_for_date(user_id, date, rating_type) do
  def get_rating_for_daily(user_id, daily_meal_plan_id) do
  def get_rating_for_meal_plan(user_id, meal_plan_id) do
  def list_ratings_for_client(client_id) do
  def change_meal_plan_rating(%MealPlanRating{} = rating, attrs \\ %{}) do

## defmodule Mehungry.SqlUtils do
  def explain_analyze(query, params \\ [], opts \\ []) do

## defmodule Mehungry.Subscriptions.UserSubscription do
  def changeset(subscription, attrs) do

## defmodule Mehungry.Subscriptions.AiUsage do
  def changeset(usage, attrs) do

## defmodule Mehungry.Billing.StripeHandler do
  def create_checkout_session(
  def create_billing_portal_session(stripe_customer_id, return_url) do
  def handle_webhook(raw_body, signature_header) do

## defmodule Mehungry.NewsLetter.Nuser do
  def changeset(nuser, attrs) do

## defmodule Mehungry.Search do
  def change_recipe_search_item(%RecipeSearchItem{} = recipe_search, attrs \\ %{}) do
  def update_recipe_search_item(%RecipeSearchItem{} = recipe_search, attrs \\ %{}) do
  def search_recipe(search_term, language_name \\ nil) do

## defmodule Mehungry.Feedback.Feedback do
  def changeset(feedback, attrs) do

## defmodule Mehungry.Repo do

## defmodule Mehungry.Professionals.TutorInvitation do
  def changeset(invitation, attrs) do

## defmodule Mehungry.Professionals.ProfessionalProfile do
  def changeset(profile, attrs) do

## defmodule Mehungry.Professionals.TutorClientAssignment do
  def changeset(assignment, attrs) do

## defmodule Mehungry.Professionals.Appointment do
  def changeset(appointment, attrs) do

## defmodule Mehungry.Professionals.MealPlanRating do
  def changeset(rating, attrs) do

## defmodule Mehungry.Food.CategoryTranslation do
  def changeset(cat_trans, attrs) do

## defmodule Mehungry.Food.Measurements do
  def get_measurement_unit!(nil), do: nil
  def get_measurement_unit!(id) do
  def get_measurement_unit_portions_for_ingredient(ingredient_id)
  def get_measurement_unit_portions_for_ingredient(ingredient_id) do
  def get_measurement_unit_portions_for_ingredients(ingredient_ids)
  def get_measurement_unit_by_name(name) do
  def create_measurement_unit(attrs) do
  def update_measurement_unit(%MeasurementUnit{} = measurement_unit, attrs \\ %{}) do
  def delete_measurement_unit(%MeasurementUnit{} = measrement_unit) do
  def change_measurement_unit(measurement_unit, attrs \\ %{}) do
  def list_measurement_units() do
  def search_measurement_unit(term) do
  def search_measurement_unit(search_term, language_str) do

## defmodule Mehungry.Food.NutrientInteractions do
  def interactions_for_ingredients(ingredient_ids) when ingredient_ids == [], do: []
  def interactions_for_ingredients(ingredient_ids) do
  def interactions_for_nutrient_map(nutrient_map) when nutrient_map == %{}, do: []
  def interactions_for_nutrient_map(nutrient_map) do
  def rules, do: @rules

## defmodule Mehungry.Food.IngredientPortion do
  def changeset(measurement_unit, attrs) do

## defmodule Mehungry.Food.Categories do
  def create_category(attrs) do
  def update_category(%Category{} = category, attrs \\ %{}) do
  def delete_category(%Category{} = category) do
  def get_category!(id) do
  def change_category(%Category{} = category, attrs \\ %{}) do
  def get_category_by_name(nil) do
  def get_category_by_name(name) do
  def list_categories() do
  def search_category(term) do
  def list_food_restriction_types() do

## defmodule Mehungry.Food.Nutrients do
  def get_nutrient(id) do
  def get_nutrient(name, measurment_unit_id) do
  def create_nutrient(attrs) do
  def list_nutrients() do
  def list_key_nutrients() do
  def enqueue_nutrient_recalculation_for_all do
  def get_interactions_for_ingredients(ingredient_ids) do
  def get_interactions_for_recipe(recipe) do
  def enqueue_interaction_recalculation_for_all do

## defmodule Mehungry.Food.MeasurementUnit do
  def changeset(measurement_unit, attrs) do

## defmodule Mehungry.Food.NutrientNameNormalizer do
  def normalize(name) when is_nil(name), do: "Unknown"
  def normalize(name) when is_atom(name), do: normalize(Atom.to_string(name))
  def normalize(name) when is_binary(name) do
  def is_fatty_acid?(name) do
  def get_fat_category(name) do

## defmodule Mehungry.Food.Engagement do
  def get_user_likes(user_id) do
  def like_recipe(user_id, recipe_id) do
  def count_user_liked_recipes(nil), do: nil
  def count_user_liked_recipes(user_id) do
  def get_recipe_comments(recipe_id) do
  def list_annotations(%Recipe{} = recipe) do

## defmodule Mehungry.Food.Recipes do
  def get_recipe_no_caching!(id) do
  def get_recipe!(id) do
  def get_recipe!(id, language_name) do
  def delete_recipe(id) do
  def change_recipe(recipe, attrs \\ %{}) do
  def change_step(%Step{} = step, attrs \\ %{}) do
  def recipe_counts_by_user_id do
  def count_user_created_recipes(nil), do: nil
  def count_user_created_recipes(user_id) do
  def count_recipes_created_by_user_ids(user_ids) do
  def count_recipes do
  def count_recipes_missing_embeddings do
  def list_recipe_ids do
  def list_user_recipes_for_selection(nil) do
  def list_user_recipes_for_selection(_user_id) do
  def list_recipes(%Ecto.Query{} = query), do: list_recipes(query, nil)
  def list_recipes(%Ecto.Query{} = query, language_name) do
  def list_recipes(cursor_after), do: list_recipes(cursor_after, nil, nil)
  def list_recipes(cursor_after, query), do: list_recipes(cursor_after, query, nil)
  def list_recipes(cursor_after, query, language_name) do
  def list_user_recipes(user_id) do
  def create_recipe(attrs \\ %{}) do
  def update_recipe(%Recipe{} = recipe_origin, attrs \\ %{}) do
  def create_post_from_recipe(%Recipe{} = recipe) do
  def put_nutrient_info(%Ecto.Changeset{valid?: true} = changeset, attrs) do

## defmodule Mehungry.Food.Annotation do
  def changeset(annotation, attrs) do

## defmodule Mehungry.Food.Recipe do
  def changeset(recipe, attrs) do

## defmodule Mehungry.Food.RecipeHashtag do
  def changeset(recipe_ingredient, attrs) do

## defmodule Mehungry.Food.Category do
  def changeset(category, attrs) do

## defmodule Mehungry.Food.IngredientQueries do
  def search_hashtag(hashtag) do
  def search_hashtag1(hashtag) do
  def search_recipes_by_ingredient(ingredient_name) do
  def list_sample_recipes_for_ingredient(ingredient_id, limit \\ 4) do
  def search_recipe(query_string, language_name \\ nil)
  def search_recipe("", language_name) do
  def search_recipe(query_string, language_name) do
  def pagenate_query(query) do
  def get_second_layer_foods_ids() do
  def maybe_filter_by_classes(query, nil), do: query
  def maybe_filter_by_classes(query, []), do: query
  def maybe_filter_by_classes(query, [""]), do: query
  def maybe_filter_by_classes(query, classes) do
  def search_ingredient_search(search_term, classes \\ []) do
  def search_ingredient_alt_admin(search_term, classes \\ []) do
  def search_ingredient_alt(search_term, classes \\ []) do
  def search_ingredient_admin(search_term, classes \\ []) do
  def search_ingredient_admin_translated(search_term, language_name, classes \\ []) do
  def search_ingredient(search_term, classes \\ []) do
  def search_ingredient_query(search_term, classes \\ []) do
  def search_ingredient3(search_term) do
  def search_ingredient2(search_term) do

## defmodule Mehungry.Food.Like do
  def changeset(like, attrs) do

## defmodule Mehungry.Food.NutrientCalculation do
  def calculate_recipe_nutrition_value(recipe) do
  def validate_ingredient_units(ingredient_params) do
  def map_ingredients_to_structured_form(recipe_ingredient_params) do
  def calculate_gram_weight(ingredient, measurement_unit_id, quantity, gram_unit_ids) do
  def build_nutrient_list(ingredient, gram_weight) do
  def filter_energy_duplicates(nutrients) do
  def calculate_nutrition_for_recipe(ingredients_with_nutrients) do
  def sort_nutrients_by_priority(nutrient_map) when is_map(nutrient_map) do
  def calculate_total_calories(nutrients) do
  def safe_to_float(value) when is_float(value), do: value
  def safe_to_float(value) when is_integer(value), do: value * 1.0
  def safe_to_float(value) when is_binary(value) do
  def safe_to_float(_), do: 0.0
  def safe_nutrient_amount(amount) when is_float(amount), do: amount
  def safe_nutrient_amount(amount) when is_integer(amount), do: amount * 1.0
  def safe_nutrient_amount(_), do: 0.0
  def get_value(map, key) do
  def get_value_specific(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value_specific(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]
  def pretty_print_nutrition(nutrition_result) do

## defmodule Mehungry.Food.IngredientSearch do
  def search(search_term, classes \\ []) do
  def search_for_select(search_term, classes \\ []) do
  def search_in_language(search_term, language_name) when is_binary(search_term) do

## defmodule Mehungry.Food.Step do
  def changeset(step, attrs) do

## defmodule Mehungry.Food.Ingredients do
  def create_ingredient_portion(attrs) do
  def broadcast_ingredient_work_item(file_url) do
  def create_ingredient_nutrient(attrs) do
  def get_ingredient_by_name(name) do
  def create_ingredient(attrs) do
  def delete_ingredient(%Ingredient{} = ingredient) do
  def delete_ingredients_without_nutrients do
  def change_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
  def update_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
  def get_ingredient_by_slug(slug) do
  def get_ingredient_by_translation_name(name) do
  def get_ingredient_details!(nil), do: nil
  def get_ingredient_details!(id) do
  def get_ingredient_with_category!(id) do
  def get_ingredient!(id) do
  def get_ingredient(id) do
  def find_ri_allias(%{"ingredient_id" => ingredient_id} = rec_in, lang_id) do
  def list_ingredients() do
  def list_ingredients_paginated() do
  def list_ingredients_paginated_translated(language_name, cursor_after \\ nil) do
  def list_ingredients_paginated(%Ecto.Query{} = query) do
  def list_ingredients_paginated(cursor_after, query \\ nil) do
  def list_recipe_ingredients() do
  def change_recipe_ingredient(%RecipeIngredient{} = recipe_ingredient, attrs \\ %{}) do

## defmodule Mehungry.Food.IngredientNutrient do
  def changeset(measurement_unit, attrs) do

## defmodule Mehungry.Food.Nutrient do
  def changeset(nutrient, attrs) do

## defmodule Mehungry.Food.FoodRestrictionType do
  def changeset(food_restriction_type, attrs) do

## defmodule Mehungry.Food.RecipeIngredient do
  def changeset(recipe_ingredient, attrs) do

## defmodule Mehungry.Food.IngredientTranslation do
  def changeset(ingredient_translation, attrs) do

## defmodule Mehungry.Food.NutrientMerger do
  def nutrient_display_priority(nutrient_name) do
  def normalize_nutrient_name(nil), do: "Unknown"
  def normalize_nutrient_name(name) when is_atom(name),
  def normalize_nutrient_name(name) when is_binary(name) do
  def get_value(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]
  def to_string_keys(nil), do: nil
  def to_string_keys(list) when is_list(list), do: Enum.map(list, &to_string_keys/1)
  def to_string_keys(%{} = map) do
  def to_string_keys(other), do: other
  def to_atom_keys(nil), do: nil
  def to_atom_keys(list) when is_list(list), do: Enum.map(list, &to_atom_keys/1)
  def to_atom_keys(%{} = map) do
  def to_atom_keys(other), do: other
  def find_parent_category(nutrient_name) do
  def normalize_units(
  def normalize_units(nutrient), do: nutrient
  def normalize_keys(nutrient) when is_list(nutrient), do: Enum.map(nutrient, &normalize_keys/1)
  def normalize_keys(%{} = nutrient) do
  def merge_nutrients(nutrient_list) when is_list(nutrient_list) do
  def merge_nutrients_to_list(nutrient_list) do
  def merge_flat_list(nutrient_list) do
  def map_to_sorted_list(merged_map) when is_map(merged_map) do
  def summarize_meals_nutrients(user_meals) do

## defmodule Mehungry.Food.Ingredient do
  def changeset(ingredient, attrs) do
  def normalize_string(str) when is_binary(str) do
  def normalize_string(_), do: ""

## defmodule Mehungry.Food.NutrientMapper do
  def init(init_arg), do: {:ok, init_arg}
  def get_nutrient_name(nutrient_id, fallback_name \\ nil) do
  def get_all_mappings, do: %{}
  def status, do: %{loaded_count: 1}
  def humanize_nutrient_name(name) when is_binary(name) do
  def humanize_nutrient_name(_), do: "Unknown Nutrient"

## defmodule Mehungry.Food.NutrientHierarchyBuilder do
  def build_hierarchy(nutrients) do

## defmodule Mehungry.Food.Localization do
  def apply_recipe_translation(recipe, nil), do: recipe
  def apply_recipe_translation(recipe, %RecipeTranslation{title: nil}), do: recipe
  def apply_recipe_translation(recipe, %RecipeTranslation{} = translation) do
  def localize_recipes(recipes, nil), do: Enum.map(recipes, &translate_recipe_if_needed/1)
  def localize_recipes(recipes, language_name) do
  def load_recipe_translations_map([], _language_name), do: %{}
  def load_recipe_translations_map(recipe_ids, language_name) do
  def translate_recipe_if_needed(recipe) do
  def ingredient_language_for("el"), do: "Gr"
  def ingredient_language_for(_), do: nil
  def translate_ingredients_to(recipe, language_name) do
  def ingredient_display_names(ingredient_ids, language_name)
  def ingredient_display_names(_ingredient_ids, _language), do: %{}
  def get_unit_translations_map(unit_ids, language_name)
  def get_unit_translations_map(_unit_ids, _language), do: %{}
  def upsert_ingredient_translation(ingredient_id, language_name, name) do
  def upsert_measurement_unit_translation(unit_id, language_name, name) do
  def count_untranslated_ingredients(language_name) do
  def ingredient_translation_stats do
  def find_ingredient_translation(language_name, ingredient_id) do

## defmodule Mehungry.Food.RecipeUtils do
  def sort_nutrients_from_db(nutrients) do
  def get_nutrients(recipe) do
  def get_nutrients_pre(rest) do
  def sort_nutrients(nutrients, energy) do
  def convert_energy_to_calories_if_needed(nil), do: nil
  def convert_energy_to_calories_if_needed(energy) do
  def get_nutrient_category(nutrients, category_name, category_sum_name) do
  def calculate_recipe_nutrition_value(recipe) do
  def map_ingredients_to_structured_form_pre_saved(nil), do: nil
  def map_ingredients_to_structured_form_pre_saved(recipe_ingredients) do
  def reform_nutrients(nutrients) do
  def map_ingredients_to_structured_form(recipe_ingredients) do
  def calculate_nutrition_for_recipe_ingredient(nil), do: nil
  def calculate_nutrition_for_recipe_ingredient(recipe_ingredients) do
  def calculate_nutrition_for_recipe_ingredient_callendar(recipe_ingredients) do
  def adjust_amount(recipe_amount, nutrient_entry, measurement_unit, ingredient_item) do
  def calculate_recipe_ingredient_categories_array(%Recipe{} = recipe) do
  def calculate_recipe_ingredient_categories_array(nil) do
  def nutrient_name_to_string(nutrient) do

## defmodule Mehungry.Food.MeasurementUnitTranslation do
  def changeset(mu_trans, attrs) do

## defmodule Mehungry.Food.Recipe.Query do
  def base, do: Recipe

## defmodule Mehungry.Social.Facebook do
  def get_user_pages(user, token, facebook_user_id) do
  def post_recipe_container(_user, recipe, page) do

## defmodule Mehungry.Social.Instagram.Token do
  def build(api_response, instagram_user_id, now \\ DateTime.utc_now()) do
  def status(token, now \\ DateTime.utc_now())
  def status(token, now) when is_map(token) do
  def status(_token, _now), do: :not_connected
  def connected?(token), do: status(token) in [:connected, :expiring]
  def expires_at(token) when is_map(token), do: parse_datetime(token["expires_at"])
  def expires_at(_token), do: nil
  def refreshable?(token, now \\ DateTime.utc_now()) do

## defmodule Mehungry.Social.Instagram.Client do
  def exchange_long_lived_token(short_lived_token) do
  def refresh_long_lived_token(access_token) do
  def create_media_container(user_id, access_token, image_url, caption) do
  def publish_media_container(user_id, access_token, container_id) do

## defmodule Mehungry.Social.Instagram.ClientBehaviour do

## defmodule Mehungry.Social.Instagram.Caption do
  def build(recipe) do
  def format_number(nil), do: ""
  def format_number(n) when is_integer(n), do: Integer.to_string(n)
  def format_number(n) when is_float(n) do

## defmodule Mehungry.Social.Instagram do
  def connect_account(%User{} = user, short_lived_token, instagram_user_id) do
  def refresh_user_token(%User{} = user) do
  def post_recipe(%User{} = user, recipe) do
  def token_status(%User{instagram_token: token}), do: Token.status(token)
  def token_status(token), do: Token.status(token)
  def list_users_with_tokens do
  def mark_stale(%User{} = user, reason) do

## defmodule Mehungry.Social.PublisherBehaviour do

## defmodule Mehungry.Social.Pinterest do
  def get_boards(user) do
  def create_pin(user, %Recipe{} = recipe, board_id) do
  def create_board(user, attrs) do

## defmodule Mehungry.Social.Publisher do
  def publish_recipe(recipe, bot_user, ai_bot_recipe_id, language_name, opts \\ %{}) do

## defmodule Mehungry.Languages.Language do
  def changeset(language, attrs) do

## defmodule Mehungry.Utils do
  def put_map(map, key, value) when map == %{} do
  def put_map(the_map, key, value) do
  def remove_parenthesis(text) do
  def sort_ingredients_for_basket(ingredients) do
  def normilize_ingredient(ingredient_params) do
  def normilize_measurement_unit(m_u, value) do
  def get_bigger_mu(measurement_unit, m_index \\ 0) do
  def get_smaller_mu(measurement_unit, m_index \\ 0) do

## defmodule Mehungry.S3 do
  def upload_file(bucket, key, file_path, opts \\ []) do
  def upload_binary(data, bucket, key, opts \\ []) do
  def download_file(bucket, key, destination_path \\ nil) do
  def list_objects(bucket, prefix \\ nil, opts \\ []) do
  def delete_object(bucket, key, request_opts \\ []) do
  def presigned_url(bucket, key, expires_in \\ 3600, operation \\ :get) do
  def object_exists?(bucket, key) do
  def create_bucket(bucket, region \\ "us-east-1", opts \\ []) do
  def delete_bucket(bucket) do

## defmodule Mehungry.AI.Agents.NutritionistAgent do
  def run(professional_id, client_id, preferences, opts \\ []) do

## defmodule Mehungry.AI.Agents.RecipeAgent do
  def run(description) do

## defmodule Mehungry.AI.Agents.MealPlanAgent do
  def run(preferences, _recipes, start_date, user_id) do

## defmodule Mehungry.AI.RecipeGenerator do
  def run(description) do

## defmodule Mehungry.AI.RecipeTranslator do
  def translate_recipe(%{title: title, description: description} = recipe, target_language_name) do

## defmodule Mehungry.AI.Agent do
  def run(system, user_message, tool_defs, handler, context, opts \\ []) do

## defmodule Mehungry.AI.IngredientTranslator do
  def translate_to_greek(ingredients) when is_list(ingredients) do

## defmodule Mehungry.AI.ImageGenerator do
  def generate(title, description) do

## defmodule Mehungry.AI.MealPlanGenerator do
  def run(preferences, recipes, start_date, user_id) do

## defmodule Mehungry.AI.Client do
  def request(params) do
  def text_from(%{content: blocks}) do

## defmodule Mehungry.AI.EmbeddingClient do
  def embed(text) when is_binary(text) do

## defmodule Mehungry.Subscriptions do
  def get_subscription(user_id) do
  def upsert_subscription(user_id, attrs) do
  def activate_pro(user_id, stripe_customer_id, stripe_subscription_id, period_end) do
  def activate_nutritionist(user_id, stripe_customer_id, stripe_subscription_id, period_end) do
  def cancel_subscription(stripe_subscription_id) do
  def update_subscription_status(stripe_subscription_id, status, period_end \\ nil) do
  def check_quota(user_id, feature) do
  def record_usage(user_id, feature) do
  def get_usage_this_month(user_id, feature) do
  def quota_status(user_id, feature) do
  def monthly_limit(tier, feature) do
  def pro?(user_id) do
  def nutritionist?(user_id) do
  def subscriptions_by_user_id do

## defmodule Mehungry.Food do

## defmodule Mehungry.Search.RecipeSearchItem do
  def changeset(%__MODULE__{} = search, attrs) do

## defmodule Mehungry.Search.RecipeVectorSearch do
  def search(query_text, opts \\ []) do

## defmodule Mehungry.Search.RecipeSearch do
  def run(query, search_string) do

## defmodule Mehungry.Accounts do

## defmodule Mehungry.NutrientUtils do
  def normalize_nutrient_name(name) when is_binary(name) do
  def normalize_nutrient_name(_), do: "Unknown"
  def merge_nutrients_with_normalization(list) do
  def nutrient_display_priority(nutrient_name) do
  def sort_nutrients_for_display(nutrients_map) do
  def summarize_meals_nutrients(user_meals) do

## defmodule Mehungry.Feedback do
  def change_feedback(attrs \\ %{}) do
  def create_feedback(attrs) do
  def list_feedbacks do
  def delete_feedback(%Feedback{} = feedback), do: Repo.delete(feedback)
  def get_feedback!(id), do: Repo.get!(Feedback, id)

## defmodule Mehungry.FoodProducts do
  def get_product_by_barcode(barcode, opts \\ []) do
  def search_products(query, opts \\ []) do
  def list_products_by_country(country_tag, opts \\ []) do
  def count_products(country_tag \\ nil) do
  def upsert_products(parsed) when is_list(parsed) do
  def known_language_codes do
  def link_product_to_ingredient(%FoodProduct{} = product, ingredient_id, score, status)
  def unlink_product(%FoodProduct{} = product) do
  def get_sync_state(key) do
  def put_sync_state(key, attrs) do

## defmodule Mehungry.Release do
  def migrate(opts \\ [all: true]) do
  def migration_status do
  def load_fdc_ingredients(file_path) do
  def import_off_products(opts \\ []) do
  def rollback(version) do

## defmodule Mehungry.Telemetry.ActionContext do
  def attach do
  def current do
  def handle_start(event, _measurements, metadata, _config) do
  def handle_stop(_event, _measurements, _metadata, _config) do

## defmodule Mehungry.Telemetry.QueryProfile do
  def changeset(profile, attrs) do

## defmodule Mehungry.Telemetry.ErrorEvent do

## defmodule Mehungry.Telemetry.Snapshot do
  def changeset(snapshot, attrs) do

## defmodule Mehungry.Telemetry.MetricsBuffer do
  def start_link(opts \\ []) do
  def init(_opts) do
  def handle_info(:flush, state) do
  def handle_repo_query(_event, measurements, metadata, _config) do
  def handle_router_dispatch(_event, measurements, metadata, _config) do
  def handle_live_view_mount(_event, measurements, metadata, _config) do
  def handle_live_view_event(_event, measurements, metadata, _config) do
  def handle_oban_job_stop(_event, measurements, metadata, _config) do
  def handle_oban_job_exception(_event, _measurements, metadata, _config) do
  def handle_cache_size(_event, measurements, metadata, _config) do
  def handle_oban_queue_depth(_event, measurements, metadata, _config) do
  def handle_vm_process_stats(_event, measurements, _metadata, _config) do
  def handle_vm_scheduler(_event, measurements, _metadata, _config) do
  def handle_vm_memory(_event, measurements, _metadata, _config) do
  def handle_vm_live_view_count(_event, measurements, _metadata, _config) do
  def handle_repo_pool_stats(_event, measurements, _metadata, _config) do
  def fingerprint_query(source, query_text) do
  def list_recent_query_events(minutes) do

## defmodule Mehungry.Telemetry.ErrorTracker do
  def start_link(opts \\ []) do
  def init(_opts) do
  def handle_cast({:error_event, event}, state) do
  def handle_plug_exception(_event, _measurements, metadata, _config) do
  def handle_live_view_exception([:phoenix, :live_view, stage, :exception], _msr, metadata, _cfg) do
  def handle_oban_exception(_event, _measurements, metadata, _config) do

## defmodule Mehungry.RateLimit do
  def hit(key, limit, window_ms)

## defmodule Mehungry.Inventory.ShoppingBasket do
  def changeset(shoping_basket, attrs) do

## defmodule Mehungry.Inventory.BasketItem do
  def changeset(basket_ingredient, attrs) do

## defmodule Mehungry.Inventory.BasketIngredient do
  def changeset(basket_ingredient, attrs) do

## defmodule Mehungry.Inventory.BasketParams do
  def changeset(%__MODULE__{} = basket, attrs) do

## defmodule Mehungry.History.ConsumeRecipeUserMeal do
  def changeset(consume_recipe_user_meal, attrs) do
  def validate_recipe_user_meal(changeset, field, portions) when is_atom(field) do

## defmodule Mehungry.History.RecipeUserMeal do
  def changeset(recipe_user_meal, attrs) do

## defmodule Mehungry.History.UserMeal do
  def changeset(user_meal, attrs) do

## defmodule Mehungry.History.IngredientUserMeal do
  def changeset(ingredient_user_meal, attrs) do

## defmodule Mehungry.Meta.Visit do
  def changeset(visit, attrs) do

## defmodule Mehungry.Languages do
  def create_language(attrs \\ %{}) do
  def update_language(%Language{} = language, attrs) do
  def change_language(_language, attrs \\ %{}) do
  def get_language!(id), do: Repo.get!(Language, id)
  def get_language_by_name(name) do
  def list_languages() do
  def delete_language(%Language{} = language) do

## defmodule Mehungry.Posts do
  def count_user_posts(nil), do: nil
  def count_user_posts(user_id) do
  def list_posts(nil) do
  def list_posts(%User{} = user) do
  def localize_for_language(posts, nil), do: posts
  def localize_for_language(posts, language_name) do
  def get_post!(id) do
  def subscribe_to_recipe(%{recipe_id: recipe_id}) do
  def subscribe_to_post(%{post_id: post_id}) do
  def create_post(%Recipe{} = recipe) do
  def create_post_for_translation(%Recipe{} = recipe, translation) do
  def post_exists_for?(recipe_id, nil) do
  def post_exists_for?(recipe_id, language_name) do
  def update_post(%Post{} = post, attrs) do
  def delete_post(%Post{} = post) do
  def change_post(%Post{} = post, attrs \\ %{}) do
  def list_comments do
  def count_user_comments(nil), do: nil
  def count_user_comments(user_id) do
  def get_comment!(id) do
  def create_comment(attrs \\ %{}) do
  def update_comment(%Comment{} = comment, attrs) do
  def delete_comment(%Comment{} = comment) do
  def change_comment(%Comment{} = comment, attrs \\ %{}) do
  def list_comment_answers do
  def get_comment_answer!(id), do: Repo.get!(CommentAnswer, id)
  def create_comment_answer(attrs \\ %{}) do
  def update_comment_answer(%CommentAnswer{} = comment_answer, attrs) do
  def delete_comment_answer(%CommentAnswer{} = comment_answer) do
  def change_comment_answer(%CommentAnswer{} = comment_answer, attrs \\ %{}) do
  def list_post_upvotes do
  def get_post_upvote!(id), do: Repo.get!(PostUpvote, id)
  def create_post_upvote(attrs \\ %{}) do
  def update_post_upvote(%PostUpvote{} = post_upvote, attrs) do
  def delete_post_upvote(%PostUpvote{} = post_upvote) do
  def change_post_upvote(%PostUpvote{} = post_upvote, attrs \\ %{}) do
  def list_post_downvotes do
  def get_post_downvote!(id), do: Repo.get!(PostDownvote, id)
  def create_post_downvote(attrs \\ %{}) do
  def downvote_post(post_id, user_id) do
  def get_comment_votes_for_user(user_id, comment_id) do
  def vote_comment(comment_id, user_id, reaction) do
  def upvote_post(post_id, user_id) do
  def delete_upvotes(user_id, post_id) do
  def delete_downvotes(user_id, post_id) do
  def get_downvote_from(user_id, post_id) do
  def get_upvote_from(user_id, post_id) do
  def update_post_downvote(%PostDownvote{} = post_downvote, attrs) do
  def delete_post_downvote(%PostDownvote{} = post_downvote) do
  def change_post_downvote(%PostDownvote{} = post_downvote, attrs \\ %{}) do
  def list_comment_votes do
  def get_comment_vote!(id), do: Repo.get!(CommentVote, id)
  def create_comment_vote(attrs \\ %{}) do
  def update_comment_vote(%CommentVote{} = comment_vote, attrs) do
  def delete_comment_vote(%CommentVote{} = comment_vote) do
  def change_comment_vote(%CommentVote{} = comment_vote, attrs \\ %{}) do
  def list_comment_answer_votes do
  def get_comment_answer_vote!(id), do: Repo.get!(CommentAnswerVote, id)
  def create_comment_answer_vote(attrs \\ %{}) do
  def update_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote, attrs) do
  def delete_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote) do
  def change_comment_answer_vote(%CommentAnswerVote{} = comment_answer_vote, attrs \\ %{}) do

## defmodule Mehungry.Inventory do
  def change_basket_params(%BasketParams{} = basket_params, attrs \\ %{}) do
  def list_shopping_baskets do
  def list_shopping_baskets_for_user(user_id) do
  def get_shopping_basket!(id) do
  def update_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs) do
  def add_item(basket_id, item_params) do
  def add_items_from_recipe(basket_id, recipe, servings_scale \\ 1) do
  def create_shopping_basket(attrs \\ %{}) do
  def delete_shopping_basket(%ShoppingBasket{} = shopping_basket) do
  def delete_all_baskets_for_user(user_id) do
  def change_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs \\ %{}) do
  def list_basket_ingredients do
  def get_shopping_basket_ingredient!(id), do: Repo.get!(BasketIngredient, id)
  def create_basket_ingredient(attrs \\ %{}) do
  def update_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs) do
  def toggle_basket_ingredient(%BasketItem{} = basket_item) do
  def toggle_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
  def delete_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
  def change_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs \\ %{}) do

## defmodule Mehungry.BackfillAllMassUnits do
  def run do

## defmodule Mehungry.BackfillAllVolumeUnits do
  def run do

## defmodule Mehungry.Hashtag do
  def changeset(hashtag, attrs) do
  def get_hashtag_by_title(title) do

## defmodule Mehungry.FoodData.OpenFoodFacts.ProductParser do
  def parse_line(json_line, %MapSet{} = known_languages) do
  def parse_api_product(product, %MapSet{} = known_languages) when is_map(product) do
  def parse_product(product, %MapSet{} = known_languages, opts) when is_map(product) do
  def normalize_barcode(barcode) when is_binary(barcode) do
  def normalize_barcode(barcode) when is_integer(barcode),
  def normalize_barcode(_), do: :skip
  def european?(countries_tags) when is_list(countries_tags) do
  def european_tags, do: @european_tags

## defmodule Mehungry.FoodData.OpenFoodFacts.ClientBehaviour do

## defmodule Mehungry.FoodData.OpenFoodFacts.Client do
  def fetch_product(barcode) do
  def fetch_delta_index do
  def download_delta(filename, dest_path) do
  def download_dump(dest_path) do

## defmodule Mehungry.FoodData.OpenFoodFacts.BulkImporter do
  def run(opts \\ []) do
  def import_file(path, opts \\ []) do

## defmodule Mehungry.FoodData.SpoonacularImporter do
  def import_recipe(spoonacular_id, user_id, api_key) do
  def fetch_for_form(spoonacular_id, user_id, api_key) do
  def search(query, api_key, number \\ 10) do
  def import_by_query(query, user_id, api_key, opts \\ []) do
  def build_recipe_attrs(data, user_id) do

## defmodule Mehungry.FoodData.Usda.FdcClient do
  def lookup(name) do

## defmodule Mehungry.FoodData.Usda.SearchClient do
  def search_foods(query, page_size \\ 10) do
  def get_food_details(fdc_id) do

## defmodule Mehungry.FoodData.Usda.SeedFileParser do
  def get_ingredients_from_food_data_central_json_file(file_path) do

## defmodule Mehungry.FoodData.Usda.FoodParser do
  def create_ingredient(attrs, nutrient_data_source \\ nil) do
  def get_ingredients_from_food_data_central_json_file(file_path) do
  def get_ingredients_from_json_body(json_body, nutrient_data_source \\ nil) do

## defmodule Mehungry.FoodProducts.FoodProductTranslation do
  def changeset(translation, attrs) do

## defmodule Mehungry.FoodProducts.SyncState do
  def changeset(sync_state, attrs) do

## defmodule Mehungry.FoodProducts.FoodProduct do
  def changeset(food_product, attrs) do
  def barcode_format, do: @barcode_format
  def match_statuses, do: @match_statuses
  def kcal_100g(%__MODULE__{nutriments: n}), do: nutriment(n, "energy-kcal_100g")
  def macro_100g(%__MODULE__{nutriments: n}, macro) do

## defmodule Mehungry.ObanWorkers.TelemetryPrunerWorker do
  def perform(_job) do

## defmodule Mehungry.ObanWorkers.InstagramTokenRefreshWorker do
  def perform(%Oban.Job{}) do

## defmodule Mehungry.RecipeImageWorker do
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do

## defmodule Mehungry.ObanWorkers.RecipeTranslationWorker do
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id, "language_name" => lang}}) do
  def enqueue(recipe_id, language_name) do

## defmodule Mehungry.RecipeCreationWorker do
  def perform(%Oban.Job{

## defmodule Mehungry.ObanWorkers.DailyRecipeGenerationWorker do
  def perform(%Oban.Job{args: args}) do

## defmodule Mehungry.ObanWorkers.NutritionistAgentWorker do
  def perform(%Oban.Job{
  def enqueue(professional_id, client_id, client_name, preferences \\ "") do
  def topic(professional_id), do: "nutritionist_agent:#{professional_id}"

## defmodule Mehungry.ObanWorkers.OffDeltaSyncWorker do
  def perform(%Oban.Job{}) do

## defmodule Mehungry.IngredientTranslationWorker do
  def perform(%Oban.Job{}) do

## defmodule Mehungry.ObanWorkers.ProductIngredientMatchWorker do
  def perform(%Oban.Job{}) do

## defmodule Mehungry.ObanWorkers.RecipeEmbeddingWorker do
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do
  def enqueue(recipe_id) do
  def enqueue_all do

## defmodule Mehungry.ObanWorkers.RecipePublishWorker do
  def perform(%Oban.Job{

## defmodule Mehungry.RecipePutNutrientsWorker do
  def perform(%Oban.Job{

## defmodule Mehungry.Meta do
  def reporting_timezone do
  def list_visits do
  def list_visits(ip_address) do
  def recent_visits(limit \\ 50) do
  def recent_visits_page(limit, offset) do
  def distinct_referrers(days \\ 30) do
  def top_pages(limit \\ 10) do
  def visits_per_day(days \\ 7) do
  def stats_today do
  def total_stats do
  def traffic_sources(days \\ 30) do
  def classify_referrer(nil), do: :direct
  def classify_referrer(""), do: :direct
  def classify_referrer(ref) do
  def get_visit!(id), do: Repo.get!(Visit, id)
  def create_visit(attrs \\ %{}) do
  def update_visit_timing(visit_id, ttfb_ms, load_ms) do
  def update_visit_recipe_timing(visit_id, elapsed_ms, server_ms, recipe_id) do
  def update_visit(%Visit{} = visit, attrs) do
  def delete_visit(%Visit{} = visit) do
  def recent_sessions(limit \\ 30, days \\ 7) do
  def user_sessions(user_id) do
  def delete_all_visits() do
  def delete_all_visits(ip_address) do
  def change_visit(%Visit{} = visit, attrs \\ %{}) do
  def organic_visits_per_day(days \\ 30) do
  def search_engine_breakdown(days \\ 30) do
  def organic_landing_pages(days \\ 30, limit \\ 15) do
  def crawler_activity(days \\ 7) do
  def search_queries_extracted(days \\ 30) do
  def is_crawler?(agent) when is_nil(agent) or agent == "", do: false
  def is_crawler?(agent) do
  def crawler_name(agent) do
