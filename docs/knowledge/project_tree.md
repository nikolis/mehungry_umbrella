apps/mehungry/lib
├── mehungry
│   ├── accounts
│   │   ├── admin.ex
│   │   ├── auth.ex
│   │   ├── grading.ex
│   │   ├── o_auth.ex
│   │   ├── profiles.ex
│   │   ├── rules.ex
│   │   ├── user_category_rule.ex
│   │   ├── user_content.ex
│   │   ├── user.ex
│   │   ├── user_follow.ex
│   │   ├── user_ingredient_rule.ex
│   │   ├── user_notifier.ex
│   │   ├── user_post.ex
│   │   ├── user_profile.ex
│   │   ├── user_recipe.ex
│   │   └── user_token.ex
│   ├── accounts.ex
│   ├── ai
│   │   ├── agent.ex
│   │   ├── agents
│   │   │   ├── meal_plan_agent.ex
│   │   │   ├── nutritionist_agent.ex
│   │   │   └── recipe_agent.ex
│   │   ├── client.ex
│   │   ├── embedding_client.ex
│   │   ├── image_generator.ex
│   │   ├── ingredient_translator.ex
│   │   ├── meal_plan_generator.ex
│   │   ├── recipe_generator.ex
│   │   └── recipe_translator.ex
│   ├── ai_bot
│   │   ├── ai_bot_config.ex
│   │   ├── ai_bot_recipe.ex
│   │   ├── day_config.ex
│   │   ├── notifier.ex
│   │   ├── recipe_translation.ex
│   │   ├── social_media_post_log.ex
│   │   └── week_config.ex
│   ├── ai_bot.ex
│   ├── api
│   ├── application.ex
│   ├── billing
│   │   └── stripe_handler.ex
│   ├── feedback
│   │   └── feedback.ex
│   ├── feedback.ex
│   ├── food
│   │   ├── annotation.ex
│   │   ├── categories.ex
│   │   ├── category.ex
│   │   ├── category_translation.ex
│   │   ├── engagement.ex
│   │   ├── food_restriction_type.ex
│   │   ├── ingredient.ex
│   │   ├── ingredient_nutrient.ex
│   │   ├── ingredient_portion.ex
│   │   ├── ingredient_queries.ex
│   │   ├── ingredient_search.ex
│   │   ├── ingredients.ex
│   │   ├── ingredient_translation.ex
│   │   ├── like.ex
│   │   ├── localization.ex
│   │   ├── measurements.ex
│   │   ├── measurement_unit.ex
│   │   ├── measurement_unit_translation.ex
│   │   ├── nutrient_calculation.ex
│   │   ├── nutrient_conversion_factors.exs
│   │   ├── nutrient.ex
│   │   ├── nutrient_hierarchy_builder.ex
│   │   ├── nutrient_interactions.ex
│   │   ├── nutrient_manager.ex
│   │   ├── nutrient_mapper.ex
│   │   ├── nutrient_name_normilizer.ex
│   │   ├── nutrients.ex
│   │   ├── recipe
│   │   │   └── query.ex
│   │   ├── recipe.ex
│   │   ├── recipe_hashtag.ex
│   │   ├── recipe_ingredient.ex
│   │   ├── recipes.ex
│   │   ├── recipe_utils.ex
│   │   └── step.ex
│   ├── food_data
│   │   ├── open_food_facts
│   │   │   ├── bulk_importer.ex
│   │   │   ├── client_behaviour.ex
│   │   │   ├── client.ex
│   │   │   └── product_parser.ex
│   │   ├── spoonacular_importer.ex
│   │   └── usda
│   │       ├── fdc_client.ex
│   │       ├── food_parser.ex
│   │       ├── search_client.ex
│   │       └── seed_file_parser.ex
│   ├── food.ex
│   ├── food_products
│   │   ├── food_product.ex
│   │   ├── food_product_translation.ex
│   │   └── sync_state.ex
│   ├── food_products.ex
│   ├── hashtag.ex
│   ├── history
│   │   ├── consume_recipe_user_meal.ex
│   │   ├── ingredient_user_meal.ex
│   │   ├── recipe_user_meal.ex
│   │   └── user_meal.ex
│   ├── history.ex
│   ├── inventory
│   │   ├── basket_ingredient.ex
│   │   ├── basket_item.ex
│   │   ├── basket_params.ex
│   │   └── shopping_basket.ex
│   ├── inventory.ex
│   ├── languages
│   │   └── language.ex
│   ├── languages.ex
│   ├── mailer.ex
│   ├── maintenance_utils
│   │   ├── backfill_all_mass_units.ex
│   │   └── backfill_all_volume_units.ex
│   ├── meta
│   │   └── visit.ex
│   ├── meta.ex
│   ├── news_letter
│   │   └── nuser.ex
│   ├── nutrient_utils.ex
│   ├── oban_workers
│   │   ├── daily_recipe_generation_worker.ex
│   │   ├── ingredient_translation_worker.ex
│   │   ├── instagram_token_refresh_worker.ex
│   │   ├── nutritionist_agent_worker.ex
│   │   ├── off_delta_sync_worker.ex
│   │   ├── product_ingredient_match_worker.ex
│   │   ├── recipe_creation_worker.ex
│   │   ├── recipe_embedding_worker.ex
│   │   ├── recipe_image_worker.ex
│   │   ├── recipe_publish_worker.ex
│   │   ├── recipe_put_nutrients_worker.ex
│   │   ├── recipe_translation_worker.ex
│   │   └── telemetry_pruner_worker.ex
│   ├── plans
│   │   ├── daily_meal_plan.ex
│   │   ├── meal.ex
│   │   ├── meal_plan.ex
│   │   └── plans.ex
│   ├── posts
│   │   ├── comment_answer.ex
│   │   ├── comment_answer_vote.ex
│   │   ├── comment.ex
│   │   ├── comment_vote.ex
│   │   ├── post_downvote.ex
│   │   ├── post.ex
│   │   └── post_upvote.ex
│   ├── posts.ex
│   ├── professionals
│   │   ├── appointment.ex
│   │   ├── meal_plan_rating.ex
│   │   ├── professional_profile.ex
│   │   ├── tutor_client_assignment.ex
│   │   └── tutor_invitation.ex
│   ├── professionals.ex
│   ├── rate_limit.ex
│   ├── release.ex
│   ├── repo.ex
│   ├── s3.ex
│   ├── search
│   │   ├── recipe_search.ex
│   │   ├── recipe_search_item.ex
│   │   └── recipe_vector_search.ex
│   ├── search.ex
│   ├── social
│   │   ├── facebook.ex
│   │   ├── instagram
│   │   │   ├── caption.ex
│   │   │   ├── client_behaviour.ex
│   │   │   ├── client.ex
│   │   │   └── token.ex
│   │   ├── instagram.ex
│   │   ├── pinterest.ex
│   │   ├── publisher_behaviour.ex
│   │   └── publisher.ex
│   ├── social_media_publisher.ex
│   ├── sql_utils.ex
│   ├── subscriptions
│   │   ├── ai_usage.ex
│   │   └── user_subscription.ex
│   ├── subscriptions.ex
│   ├── telemetry
│   │   ├── action_context.ex
│   │   ├── error_event.ex
│   │   ├── error_tracker.ex
│   │   ├── metrics_buffer.ex
│   │   ├── query_profile.ex
│   │   └── snapshot.ex
│   ├── users.ex
│   └── utils.ex
├── mehungry.ex
└── mix
    └── tasks
        ├── dedupe_aliases.ex
        ├── import_off_products.ex
        ├── knowledge.schemas.ex
        └── translate_ingredients.ex
apps/mehungry_web/lib
├── mehungry_web
│   ├── application.ex
│   ├── bar_chart.ex
│   ├── channels
│   │   └── user_socket.ex
│   ├── components
│   │   ├── accordion_component.ex
│   │   ├── core_components.ex
│   │   ├── nutrition_accordion.ex
│   │   ├── recipe_components.ex
│   │   ├── recipe_details_tabs_config.ex
│   │   ├── select_component
│   │   │   ├── select_component_deep.ex
│   │   │   ├── select_component.ex
│   │   │   └── select_components_utils.ex
│   │   ├── svg_components.ex
│   │   └── tabs_component.ex
│   ├── controllers
│   │   ├── auth_controller.ex
│   │   ├── bot_oauth_controller.ex
│   │   ├── consent_controller.ex
│   │   ├── cookies_policy_controller.ex
│   │   ├── cookies_policy_html
│   │   │   └── index.html.heex
│   │   ├── cookies_policy_html.ex
│   │   ├── health_controller.ex
│   │   ├── home_page_controller.ex
│   │   ├── home_page_html
│   │   │   └── landing.html.heex
│   │   ├── sitemap_controller.ex
│   │   ├── stripe_webhook_controller.ex
│   │   ├── user_auth.ex
│   │   ├── user_confirmation_controller.ex
│   │   ├── user_language_controller.ex
│   │   ├── user_registration_controller.ex
│   │   ├── user_reset_password_controller.ex
│   │   ├── user_session_controller.ex
│   │   └── user_settings_controller.ex
│   ├── distributed_task_handler.ex
│   ├── endpoint.ex
│   ├── gettext.ex
│   ├── heex_ignore.ex
│   ├── helpers
│   │   └── format_helpers.ex
│   ├── image_processing.ex
│   ├── live
│   │   ├── admin_auth_live.ex
│   │   ├── calendar_live
│   │   │   ├── calendar
│   │   │   │   ├── locale.ex
│   │   │   │   ├── pie_chart.ex
│   │   │   │   ├── utils.ex
│   │   │   │   └── widget.ex
│   │   │   ├── components
│   │   │   │   ├── consume_recipe_user_meal.html.heex
│   │   │   │   ├── ingredient_user_meal.html.heex
│   │   │   │   └── recipe_user_meal.html.heex
│   │   │   ├── components.ex
│   │   │   ├── index.ex
│   │   │   ├── index.html.heex
│   │   │   ├── meal_form_component.ex
│   │   │   └── meal_form_component.html.heex
│   │   ├── create_recipe_live
│   │   │   ├── index.ex
│   │   │   ├── index.html.heex
│   │   │   ├── ingredient_component.ex
│   │   │   ├── recipe_form_component.ex
│   │   │   └── step_component.ex
│   │   ├── endpoint_times_page.ex
│   │   ├── errors_page.ex
│   │   ├── feedback_live
│   │   │   └── index.ex
│   │   ├── food_detail_live
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── foods_live
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── home_live
│   │   │   ├── components
│   │   │   │   └── post_card.html.heex
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── landing_live.ex
│   │   ├── live_helpers.ex
│   │   ├── maybe_user_auth_live.ex
│   │   ├── must_be_login_component.ex
│   │   ├── nutritionist_auth_live.ex
│   │   ├── nutritionist_live
│   │   │   ├── appointment_calendar.ex
│   │   │   ├── client_calendar.ex
│   │   │   ├── client_detail.ex
│   │   │   ├── clients.ex
│   │   │   ├── dashboard.ex
│   │   │   ├── invitations.ex
│   │   │   └── user_invitations.ex
│   │   ├── onboarding
│   │   │   └── form_component.ex
│   │   ├── privacy_policy_live.ex
│   │   ├── professional_live
│   │   │   ├── active_users.ex
│   │   │   ├── active_users.html.heex
│   │   │   ├── ai_bot_live
│   │   │   │   ├── config.ex
│   │   │   │   ├── recipe_review.ex
│   │   │   │   ├── recipe_translate.ex
│   │   │   │   ├── review_queue.ex
│   │   │   │   └── social_accounts.ex
│   │   │   ├── analytics_live.ex
│   │   │   ├── analytics_live.html.heex
│   │   │   ├── feedback_live.ex
│   │   │   ├── ingredient_live
│   │   │   │   ├── ingredient_form_component.ex
│   │   │   │   ├── ingredients_create.ex
│   │   │   │   ├── ingredients_edit.ex
│   │   │   │   ├── nutrient_component.ex
│   │   │   │   ├── portion_component.ex
│   │   │   │   ├── show.ex
│   │   │   │   ├── show.html.heex
│   │   │   │   └── translation_component.ex
│   │   │   ├── ingredients.ex
│   │   │   ├── ingredients.html.heex
│   │   │   ├── language_live
│   │   │   │   ├── form_component.ex
│   │   │   │   ├── form_component.html.heex
│   │   │   │   ├── index.ex
│   │   │   │   ├── index.html.heex
│   │   │   │   ├── show.ex
│   │   │   │   └── show.html.heex
│   │   │   ├── maintenance_live.ex
│   │   │   ├── S3BrowserLive.ex
│   │   │   ├── seo_live.ex
│   │   │   ├── seo_live.html.heex
│   │   │   ├── user.ex
│   │   │   ├── user.html.heex
│   │   │   ├── users.ex
│   │   │   └── users.html.heex
│   │   ├── profile_live
│   │   │   ├── form_category_component.ex
│   │   │   ├── form_component.ex
│   │   │   ├── form_ingredient_component.ex
│   │   │   ├── index.ex
│   │   │   ├── index.html.heex
│   │   │   ├── show.ex
│   │   │   └── show.html.heex
│   │   ├── query_timeline_page.ex
│   │   ├── query_times_page.ex
│   │   ├── recipe_browser_live
│   │   │   ├── components
│   │   │   │   ├── comment.html.heex
│   │   │   │   └── must_login.html.heex
│   │   │   ├── components.ex
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── recipe_details_live
│   │   │   ├── components
│   │   │   │   ├── comment_form.html.heex
│   │   │   │   ├── comment.html.heex
│   │   │   │   ├── form_component_comment_answer.ex
│   │   │   │   └── form_component_comment.ex
│   │   │   ├── recipe_details_component.ex
│   │   │   └── social_media_post_component.ex
│   │   ├── search_live
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── shopping_basket_live
│   │   │   ├── basic_form_component.ex
│   │   │   ├── components.ex
│   │   │   ├── form_component.ex
│   │   │   ├── index.ex
│   │   │   ├── index.html.heex
│   │   │   └── signle_item_form_component.ex
│   │   ├── upgrade_live
│   │   │   ├── index.ex
│   │   │   └── index.html.heex
│   │   ├── user_auth_live.ex
│   │   └── visit_live
│   │       ├── index.ex
│   │       ├── index.html.heex
│   │       ├── show.ex
│   │       └── show.html.heex
│   ├── live_utils.ex
│   ├── path_plug.ex
│   ├── plugs
│   │   ├── cache_raw_body.ex
│   │   ├── cookie_consent.ex
│   │   ├── registration_throttle.ex
│   │   └── require_admin.ex
│   ├── presence.ex
│   ├── release.ex
│   ├── router.ex
│   ├── seeds_gen_server.ex
│   ├── simple_s3_upload.ex
│   ├── social_media_publisher.ex
│   ├── telemetry.ex
│   ├── templates
│   │   ├── layout
│   │   │   └── _user_menu.html.heex
│   │   ├── page
│   │   │   └── index.html.eex
│   │   ├── user_confirmation
│   │   │   ├── edit.html.heex
│   │   │   └── new.html.heex
│   │   ├── user_registration
│   │   │   └── new.html.heex
│   │   ├── user_reset_password
│   │   │   ├── edit.html.heex
│   │   │   └── new.html.heex
│   │   ├── user_session
│   │   │   └── new.html.heex
│   │   └── user_settings
│   │       └── edit.html.heex
│   ├── turnstile.ex
│   ├── ueberauth
│   │   └── strategy
│   │       ├── facebook
│   │       │   └── oath.ex
│   │       ├── facebook.ex
│   │       ├── instagram
│   │       │   └── oath.ex
│   │       ├── instagram.ex
│   │       ├── pinterest
│   │       │   └── oath.ex
│   │       └── pinterest.ex
│   ├── views
│   │   ├── auth_view.ex
│   │   ├── error_helpers.ex
│   │   ├── error_view.ex
│   │   ├── layout
│   │   │   ├── layout_view.ex
│   │   │   └── templates
│   │   │       ├── admin_live.heex
│   │   │       ├── admin_root.heex
│   │   │       ├── app.html.eex
│   │   │       ├── footer.html.heex
│   │   │       ├── head.html.heex
│   │   │       ├── landing_live.heex
│   │   │       ├── live.html.heex
│   │   │       ├── menu
│   │   │       │   ├── main_menu.html.heex
│   │   │       │   └── mobile_menu.html.heex
│   │   │       ├── nutritionist_live.heex
│   │   │       └── root.html.heex
│   │   ├── user_confirmation_view.ex
│   │   ├── user_registration_view.ex
│   │   ├── user_reset_password_view.ex
│   │   ├── user_session_view.ex
│   │   └── user_settings_view.ex
│   └── visitor_plug.ex
├── mehungry_web.ex
└── viewport_helpers.ex

84 directories, 374 files
