defmodule Mehungry.Users do
  @moduledoc """
  Deprecated facade kept for existing call sites. The implementation lives in
  the Accounts context: `Mehungry.Accounts.UserContent` (saved recipes/posts,
  follows) and `Mehungry.Accounts.Grading` (personalized recipe grading).
  New code should call those modules (or `Mehungry.Accounts`) directly.
  """

  alias Mehungry.Accounts.{Grading, UserContent}

  # ── Grading ────────────────────────────────────────────────────────────

  defdelegate calculate_recipe_grading(recipe, user), to: Grading
  defdelegate calculate_recipe_grading(recipe, user_pref_table, follow_ids), to: Grading
  defdelegate calculate_user_pref_table(user), to: Grading
  defdelegate get_category_name(category), to: Grading
  defdelegate get_user_category_rules(user), to: Grading
  defdelegate get_user_category_rulles(user), to: Grading

  # ── Saved content and follows ──────────────────────────────────────────

  defdelegate save_user_recipe(user_id, recipe_id), to: UserContent
  defdelegate save_user_post(user_id, post_id), to: UserContent
  defdelegate save_user_follow(user_id, follow_id), to: UserContent
  defdelegate remove_user_saved_recipe(user_id, recipe_id), to: UserContent
  defdelegate remove_user_saved_post(user_id, post_id), to: UserContent
  defdelegate remove_user_follow(user_id, follow_id), to: UserContent
  defdelegate list_user_saved_recipes(user), to: UserContent
  defdelegate list_user_saved_recipe_ids(user), to: UserContent
  defdelegate list_user_follows(user), to: UserContent
  defdelegate list_user_saved_posts(user), to: UserContent
  defdelegate list_user_created_recipes(user), to: UserContent
  defdelegate remove_recipe_from_users_list(user, recipe), to: UserContent
  defdelegate create_user_restriction_type(attrs), to: UserContent

  # ── Rules / restriction types (canonical homes) ────────────────────────

  defdelegate list_food_restriction_types(), to: Mehungry.Food
  defdelegate create_user_category_rule(attrs), to: Mehungry.Accounts
  defdelegate list_user_category_rules(), to: Mehungry.Accounts
end
