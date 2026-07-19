# Domain Graph

## Mehungry.AI.Bot.AiBotConfig

- belongs_to bot_user -> Mehungry.Accounts.User
- has_many ai_bot_recipes -> Mehungry.AI.Bot.AiBotRecipe
- has_many week_configs -> Mehungry.AI.Bot.WeekConfig
- has_many day_configs -> Mehungry.AI.Bot.DayConfig


## Mehungry.AI.Bot.AiBotRecipe

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig
- has_many social_media_post_logs -> Mehungry.AI.Bot.SocialMediaPostLog


## Mehungry.AI.Bot.DayConfig

- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig


## Mehungry.AI.Bot.RecipeTranslation

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.AI.Bot.SocialMediaPostLog

- belongs_to ai_bot_recipe -> Mehungry.AI.Bot.AiBotRecipe


## Mehungry.AI.Bot.WeekConfig

- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig


## Mehungry.Accounts.User

- has_one recipes -> Mehungry.Food.Recipe
- has_one user_profile -> Mehungry.Accounts.UserProfile


## Mehungry.Accounts.UserCategoryRule

- belongs_to user_profile -> UserProfile
- belongs_to category -> Mehungry.Food.Category
- belongs_to food_restriction_type -> Mehungry.Food.FoodRestrictionType


## Mehungry.Accounts.UserFollow

- belongs_to user -> User
- belongs_to follow -> User


## Mehungry.Accounts.UserIngredientRule

- belongs_to user_profile -> UserProfile


## Mehungry.Accounts.UserPost

- belongs_to user -> User
- belongs_to post -> Post


## Mehungry.Accounts.UserProfile

- belongs_to user -> Mehungry.Accounts.User
- has_many user_category_rules -> Mehungry.Accounts.UserCategoryRule
- has_many user_ingredient_rules -> Mehungry.Accounts.UserIngredientRule


## Mehungry.Accounts.UserRecipe

- belongs_to user -> User
- belongs_to recipe -> Recipe


## Mehungry.Accounts.UserToken

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Feedback.Feedback

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Food.Annotation

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe


## Mehungry.Food.Category

- has_many category_translation -> CategoryTranslation


## Mehungry.Food.CategoryTranslation

- belongs_to category -> Mehungry.Food.Category
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.Food.FoodRestrictionType




## Mehungry.Food.Ingredient

- belongs_to category -> Mehungry.Food.Category
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit
- has_many ingredient_portions -> IngredientPortion
- has_many ingredient_nutrients -> IngredientNutrient
- has_many ingredient_translation -> Mehungry.Food.IngredientTranslation


## Mehungry.Food.IngredientNutrient

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to nutrient -> Mehungry.Food.Nutrient


## Mehungry.Food.IngredientPortion

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.IngredientTranslation

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.Food.Like

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe


## Mehungry.Food.MeasurementUnit

- has_many ingredient_portions -> Mehungry.Food.IngredientPortion
- has_many translation -> MeasurementUnitTranslation


## Mehungry.Food.MeasurementUnitTranslation

- belongs_to language -> Mehungry.Languages.Language
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.Nutrient

- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.Recipe

- has_many user_recipes -> Mehungry.Accounts.UserRecipe
- has_one post -> Mehungry.Posts.Post
- belongs_to user -> User
- belongs_to language -> Language
- has_many recipe_ingredients -> Mehungry.Food.RecipeIngredient
- has_many recipe_hashtags -> Mehungry.Food.RecipeHashtag
- has_many annotations -> Mehungry.Food.Annotation
- has_many comments -> Mehungry.Posts.Comment
- embeds_many steps -> Mehungry.Food.Step


## Mehungry.Food.RecipeHashtag

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to hashtag -> Mehungry.Hashtag


## Mehungry.Food.RecipeIngredient

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit
- belongs_to ingredient -> Mehungry.Food.Ingredient


## Mehungry.FoodProducts.FoodProduct

- belongs_to ingredient -> Mehungry.Food.Ingredient
- has_many translations -> Mehungry.FoodProducts.FoodProductTranslation


## Mehungry.FoodProducts.FoodProductTranslation

- belongs_to food_product -> Mehungry.FoodProducts.FoodProduct
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.FoodProducts.SyncState




## Mehungry.Hashtag

- has_many recipe_hashtags -> Mehungry.Food.RecipeHashtag


## Mehungry.History.ConsumeRecipeUserMeal

- belongs_to recipe_user_meal -> RecipeUserMeal
- belongs_to user_meal -> UserMeal


## Mehungry.History.IngredientUserMeal

- belongs_to ingredient -> Ingredient
- belongs_to user_meal -> UserMeal
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.History.RecipeUserMeal

- belongs_to recipe -> Recipe
- belongs_to user_meal -> UserMeal
- has_many consume_recipe_user_meals -> ConsumeRecipeUserMeal


## Mehungry.History.UserMeal

- has_many recipe_user_meals -> RecipeUserMeal
- has_many ingredient_user_meals -> IngredientUserMeal
- has_many consume_recipe_user_meals -> ConsumeRecipeUserMeal


## Mehungry.Inventory.BasketIngredient

- belongs_to measurement_unit -> MeasurementUnit
- belongs_to ingredient -> Ingredient
- belongs_to shopping_basket -> ShoppingBasket


## Mehungry.Inventory.BasketItem

- belongs_to measurement_unit -> MeasurementUnit
- belongs_to shopping_basket -> ShoppingBasket
- belongs_to recipe -> Recipe


## Mehungry.Inventory.ShoppingBasket

- belongs_to user -> User
- has_many basket_ingredients -> BasketIngredient
- has_many basket_items -> BasketItem


## Mehungry.Languages.Language




## Mehungry.Meta.Visit




## Mehungry.Plans.DailyMealPlan

- has_many meals -> Meal
- belongs_to meal_plan -> MealPlan


## Mehungry.Plans.Meal

- belongs_to recipe -> Recipe
- belongs_to daily_meal_plan -> DailyMealPlan


## Mehungry.Plans.MealPlan

- has_many daily_meal_plans -> DailyMealPlan


## Mehungry.Posts.Comment

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to user -> Mehungry.Accounts.User
- belongs_to post -> Mehungry.Posts.Post
- has_many comment_answers -> Mehungry.Posts.CommentAnswer
- has_many votes -> Mehungry.Posts.CommentVote


## Mehungry.Posts.CommentAnswer

- belongs_to comment -> Mehungry.Posts.Comment
- belongs_to user -> Mehungry.Accounts.User
- has_many votes -> Mehungry.Posts.CommentAnswerVote


## Mehungry.Posts.CommentAnswerVote

- belongs_to comment_answer -> Mehungry.Posts.CommentAnswer
- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Posts.CommentVote

- belongs_to comment -> Mehungry.Posts.Comment
- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Posts.Post

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to reference -> Mehungry.Food.Recipe
- has_many comments -> Comment
- has_many upvotes -> PostUpvote
- has_many downvotes -> PostDownvote


## Mehungry.Posts.PostDownvote




## Mehungry.Posts.PostUpvote




## Mehungry.Professionals.Appointment

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Professionals.MealPlanRating

- belongs_to user -> Mehungry.Accounts.User
- belongs_to daily_meal_plan -> Mehungry.Plans.DailyMealPlan
- belongs_to meal_plan -> Mehungry.Plans.MealPlan


## Mehungry.Professionals.ProfessionalProfile

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Professionals.TutorClientAssignment

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Professionals.TutorInvitation

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Subscriptions.AiUsage

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Subscriptions.UserSubscription

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Telemetry.ErrorEvent




## Mehungry.Telemetry.QueryProfile




## Mehungry.Telemetry.Snapshot


