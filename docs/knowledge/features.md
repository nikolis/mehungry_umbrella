# Features

## accounts
- apps/mehungry/lib/mehungry/accounts/user_ingredient_rule.ex
- apps/mehungry/lib/mehungry/accounts/user_notifier.ex
- apps/mehungry/lib/mehungry/accounts/user_category_rule.ex
- apps/mehungry/lib/mehungry/accounts/user_follow.ex
- apps/mehungry/lib/mehungry/accounts/user_recipe.ex
- apps/mehungry/lib/mehungry/accounts/user_post.ex
- apps/mehungry/lib/mehungry/accounts/user_profile.ex
- apps/mehungry/lib/mehungry/accounts/user_token.ex
- apps/mehungry/lib/mehungry/accounts/user.ex

## ai
- apps/mehungry/lib/mehungry/ai/agents/nutritionist_agent.ex
- apps/mehungry/lib/mehungry/ai/agents/recipe_agent.ex
- apps/mehungry/lib/mehungry/ai/agents/meal_plan_agent.ex
- apps/mehungry/lib/mehungry/ai/recipe_generator.ex
- apps/mehungry/lib/mehungry/ai/recipe_translator.ex
- apps/mehungry/lib/mehungry/ai/agent.ex
- apps/mehungry/lib/mehungry/ai/ingredient_translator.ex
- apps/mehungry/lib/mehungry/ai/image_generator.ex
- apps/mehungry/lib/mehungry/ai/meal_plan_generator.ex
- apps/mehungry/lib/mehungry/ai/client.ex

## ai_bot
- apps/mehungry/lib/mehungry/ai_bot/day_config.ex
- apps/mehungry/lib/mehungry/ai_bot/ai_bot_recipe.ex
- apps/mehungry/lib/mehungry/ai_bot/week_config.ex
- apps/mehungry/lib/mehungry/ai_bot/ai_bot_config.ex
- apps/mehungry/lib/mehungry/ai_bot/notifier.ex
- apps/mehungry/lib/mehungry/ai_bot/recipe_translation.ex
- apps/mehungry/lib/mehungry/ai_bot/social_media_post_log.ex

## apis
- apps/mehungry/lib/mehungry/apis/the_mealdb_parser.ex
- apps/mehungry/lib/mehungry/apis/spoonacular_importer.ex

## billing
- apps/mehungry/lib/mehungry/billing/stripe_handler.ex

## fdc_utils
- apps/mehungry/lib/mehungry/fdc_utils/fdc_food_parser_spliter.ex
- apps/mehungry/lib/mehungry/fdc_utils/fdc_food_parser_leg.ex
- apps/mehungry/lib/mehungry/fdc_utils/fdc_food_parser.ex

## feedback
- apps/mehungry/lib/mehungry/feedback/feedback.ex

## food
- apps/mehungry/lib/mehungry/food/category_translation.ex
- apps/mehungry/lib/mehungry/food/nutrient_interactions.ex
- apps/mehungry/lib/mehungry/food/ingredient_portion.ex
- apps/mehungry/lib/mehungry/food/measurement_unit.ex
- apps/mehungry/lib/mehungry/food/nutrient_name_normilizer.ex
- apps/mehungry/lib/mehungry/food/annotation.ex
- apps/mehungry/lib/mehungry/food/recipe.ex
- apps/mehungry/lib/mehungry/food/recipe_hashtag.ex
- apps/mehungry/lib/mehungry/food/category.ex
- apps/mehungry/lib/mehungry/food/like.ex
- apps/mehungry/lib/mehungry/food/nutrient_calculation.ex
- apps/mehungry/lib/mehungry/food/ingredient_search.ex
- apps/mehungry/lib/mehungry/food/step.ex
- apps/mehungry/lib/mehungry/food/ingredient_nutrient.ex
- apps/mehungry/lib/mehungry/food/nutrient.ex
- apps/mehungry/lib/mehungry/food/food_restriction_type.ex
- apps/mehungry/lib/mehungry/food/recipe_ingredient.ex
- apps/mehungry/lib/mehungry/food/ingredient_translation.ex
- apps/mehungry/lib/mehungry/food/nutrient_manager.ex
- apps/mehungry/lib/mehungry/food/ingredient.ex
- apps/mehungry/lib/mehungry/food/nutrient_hierarchy_builder.ex
- apps/mehungry/lib/mehungry/food/recipe_utils.ex
- apps/mehungry/lib/mehungry/food/measurement_unit_translation.ex
- apps/mehungry/lib/mehungry/food/recipe/query.ex

## history
- apps/mehungry/lib/mehungry/history/consume_recipe_user_meal.ex
- apps/mehungry/lib/mehungry/history/recipe_user_meal.ex
- apps/mehungry/lib/mehungry/history/user_meal.ex
- apps/mehungry/lib/mehungry/history/ingredient_user_meal.ex

## inventory
- apps/mehungry/lib/mehungry/inventory/basket_slection_params.ex
- apps/mehungry/lib/mehungry/inventory/shopping_basket.ex
- apps/mehungry/lib/mehungry/inventory/basket_item.ex
- apps/mehungry/lib/mehungry/inventory/basket_ingredient.ex
- apps/mehungry/lib/mehungry/inventory/basket_params.ex

## languages
- apps/mehungry/lib/mehungry/languages/language.ex

## maintenance_utils
- apps/mehungry/lib/mehungry/maintenance_utils/backfill_all_mass_units.ex
- apps/mehungry/lib/mehungry/maintenance_utils/backfill_all_volume_units.ex

## meta
- apps/mehungry/lib/mehungry/meta/visit.ex

## news_letter
- apps/mehungry/lib/mehungry/news_letter/nuser.ex

## oban_workers
- apps/mehungry/lib/mehungry/oban_workers/recipe_image_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/recipe_translation_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/recipe_creation_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/daily_recipe_generation_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/nutritionist_agent_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/ingredient_translation_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/recipe_publish_worker.ex
- apps/mehungry/lib/mehungry/oban_workers/recipe_put_nutrients_worker.ex

## plans
- apps/mehungry/lib/mehungry/plans/plans.ex
- apps/mehungry/lib/mehungry/plans/meal_plan.ex
- apps/mehungry/lib/mehungry/plans/daily_meal_plan.ex
- apps/mehungry/lib/mehungry/plans/meal.ex

## posts
- apps/mehungry/lib/mehungry/posts/post.ex
- apps/mehungry/lib/mehungry/posts/comment.ex
- apps/mehungry/lib/mehungry/posts/comment_answer_vote.ex
- apps/mehungry/lib/mehungry/posts/post_downvote.ex
- apps/mehungry/lib/mehungry/posts/post_upvote.ex
- apps/mehungry/lib/mehungry/posts/comment_vote.ex
- apps/mehungry/lib/mehungry/posts/comment_answer.ex

## professionals
- apps/mehungry/lib/mehungry/professionals/tutor_invitation.ex
- apps/mehungry/lib/mehungry/professionals/professional_profile.ex
- apps/mehungry/lib/mehungry/professionals/tutor_client_assignment.ex
- apps/mehungry/lib/mehungry/professionals/appointment.ex
- apps/mehungry/lib/mehungry/professionals/meal_plan_rating.ex

## search
- apps/mehungry/lib/mehungry/search/recipe_search_item.ex
- apps/mehungry/lib/mehungry/search/recipe_search.ex

## social_media_posts
- apps/mehungry/lib/mehungry/social_media_posts/instagram.ex

## subscriptions
- apps/mehungry/lib/mehungry/subscriptions/user_subscription.ex
- apps/mehungry/lib/mehungry/subscriptions/ai_usage.ex

## usda
- apps/mehungry/lib/mehungry/usda/fdc_client.ex
