defmodule Mehungry.Accounts do
  @moduledoc """
  Facade for the Accounts context.

  The implementation is split by concern into sub-modules; every public
  function remains callable through this module so existing call sites keep
  working. New code may call the sub-modules directly:

    * `Mehungry.Accounts.Auth` — email/password auth, sessions, confirmation
    * `Mehungry.Accounts.OAuth` — third-party auth and provider tokens
    * `Mehungry.Accounts.Profiles` — user profiles, language, counts
    * `Mehungry.Accounts.Rules` — category/ingredient dietary rules
    * `Mehungry.Accounts.Admin` — lookups, listings, deletion, alias dedupe
    * `Mehungry.Accounts.UserContent` — saved recipes/posts and follows
    * `Mehungry.Accounts.Grading` — personalized recipe grading
  """

  alias Mehungry.Accounts.{Admin, Auth, OAuth, Profiles, Rules}

  # ── Admin / lookups ────────────────────────────────────────────────────

  defdelegate get_user_by_email(email), to: Admin
  defdelegate get_user_by_canonical_email(email), to: Admin
  defdelegate get_user!(id), to: Admin
  defdelegate list_users(filters \\ %{}), to: Admin
  defdelegate count_users(), to: Admin
  defdelegate dedupe_alias_accounts(opts \\ []), to: Admin
  defdelegate delete_user(user), to: Admin

  # ── Email/password auth ────────────────────────────────────────────────

  defdelegate get_user_by_email_and_password(email, password), to: Auth
  defdelegate register_user(attrs), to: Auth
  defdelegate change_user_registration(user, attrs \\ %{}), to: Auth
  defdelegate change_user_email(user, attrs \\ %{}), to: Auth
  defdelegate apply_user_email(user, password, attrs), to: Auth
  defdelegate update_user_email(user, token), to: Auth

  defdelegate deliver_update_email_instructions(user, current_email, update_email_url_fun),
    to: Auth

  defdelegate change_user_password(user, attrs \\ %{}), to: Auth
  defdelegate update_user_password(user, password, attrs), to: Auth
  defdelegate generate_user_session_token(user), to: Auth
  defdelegate get_user_by_session_token(token), to: Auth
  defdelegate delete_session_token(token), to: Auth
  defdelegate deliver_user_confirmation_instructions(user, confirmation_url_fun), to: Auth
  defdelegate confirm_user(token), to: Auth
  defdelegate confirm_user_multi(user), to: Auth
  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun), to: Auth
  defdelegate get_user_by_reset_password_token(token), to: Auth
  defdelegate reset_user_password(user, attrs), to: Auth

  # ── OAuth ──────────────────────────────────────────────────────────────

  defdelegate get_user_tokens(user, domain), to: OAuth
  defdelegate put_user_token(user, token, domain), to: OAuth
  defdelegate update_user(user, attrs), to: OAuth
  defdelegate update_user_tokens(user, attrs), to: OAuth
  defdelegate register_3rd_party_user(attrs), to: OAuth
  defdelegate verify_3rd_party_user_changes(auth, user), to: OAuth
  defdelegate find_or_create(auth), to: OAuth
  defdelegate maybe_confirm_user(user), to: OAuth

  # ── Profiles ───────────────────────────────────────────────────────────

  defdelegate list_user_profiles(), to: Profiles
  defdelegate get_user_profile!(id), to: Profiles
  defdelegate get_user_profile_by_user_id(id), to: Profiles
  defdelegate create_user_profile(attrs \\ %{}), to: Profiles
  defdelegate update_user_profile(user_profile, attrs), to: Profiles
  defdelegate update_user_language(profile, lang), to: Profiles
  defdelegate get_user_language(user_id), to: Profiles
  defdelegate delete_user_profile(user_profile), to: Profiles
  defdelegate change_user_profile(user_profile, attrs \\ %{}), to: Profiles
  defdelegate list_opted_in_condition_ids(user_profile_id), to: Profiles
  defdelegate diet_mode(user_or_id), to: Profiles
  defdelegate diet_mode_for_diet(diet), to: Profiles
  defdelegate set_condition_opt_ins(user_profile_id, condition_ids), to: Profiles
  defdelegate get_user_essentials(user), to: Profiles
  defdelegate count_user_following(user_id), to: Profiles
  defdelegate count_user_followers(user_id), to: Profiles
  defdelegate count_user_saved_recipes(user_id), to: Profiles

  # ── Dietary rules ──────────────────────────────────────────────────────

  defdelegate list_user_category_rules(), to: Rules
  defdelegate get_user_category_rule!(id), to: Rules
  defdelegate create_user_category_rule(attrs \\ %{}), to: Rules
  defdelegate update_user_category_rule(user_category_rule, attrs), to: Rules
  defdelegate delete_user_category_rule(user_category_rule), to: Rules
  defdelegate change_user_category_rule(user_category_rule, attrs \\ %{}), to: Rules
  defdelegate list_user_ingredient_rules(), to: Rules
  defdelegate get_user_ingredient_rule!(id), to: Rules
  defdelegate create_user_ingredient_rule(attrs \\ %{}), to: Rules
  defdelegate update_user_ingredient_rule(user_ingredient_rule, attrs), to: Rules
  defdelegate delete_user_ingredient_rule(user_ingredient_rule), to: Rules
  defdelegate change_user_ingredient_rule(user_ingredient_rule, attrs \\ %{}), to: Rules
end
