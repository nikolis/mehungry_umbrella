# Schema Inventory

## Mehungry.AI.Bot.AiBotConfig

**Table:** `ai_bot_configs`

### Fields

- theme: :string
- month: :integer
- year: :integer
- active: :boolean
- pinterest_default_board_id: :string
- facebook_page_id: :string
- publish_times: :map
- facebook_page_ids: :map
- pinterest_board_ids: :map
- timestamps: timestamps

### Relationships

- belongs_to bot_user -> Mehungry.Accounts.User
- has_many ai_bot_recipes -> Mehungry.AI.Bot.AiBotRecipe
- has_many week_configs -> Mehungry.AI.Bot.WeekConfig
- has_many day_configs -> Mehungry.AI.Bot.DayConfig


## Mehungry.AI.Bot.AiBotRecipe

**Table:** `ai_bot_recipes`

### Fields

- meal_type: :string
- scheduled_date: :date
- status: :string
- timestamps: timestamps

### Relationships

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig
- has_many social_media_post_logs -> Mehungry.AI.Bot.SocialMediaPostLog


## Mehungry.AI.Bot.DayConfig

**Table:** `ai_bot_day_configs`

### Fields

- date: :date
- focus_hint: :string
- timestamps: timestamps

### Relationships

- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig


## Mehungry.AI.Bot.RecipeTranslation

**Table:** `recipe_translations`

### Fields

- title: :string
- description: :string
- steps: {:array, :map}
- timestamps: timestamps

### Relationships

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.AI.Bot.SocialMediaPostLog

**Table:** `social_media_post_logs`

### Fields

- platform: :string
- status: :string
- language_name: :string
- error: :string
- posted_at: :utc_datetime
- target_id: :string
- target_name: :string
- timestamps: timestamps

### Relationships

- belongs_to ai_bot_recipe -> Mehungry.AI.Bot.AiBotRecipe


## Mehungry.AI.Bot.WeekConfig

**Table:** `ai_bot_week_configs`

### Fields

- week_number: :integer
- theme: :string
- timestamps: timestamps

### Relationships

- belongs_to bot_config -> Mehungry.AI.Bot.AiBotConfig


## Mehungry.Accounts.User

**Table:** `users`

### Fields

- email: :string
- canonical_email: :string
- password: :string
- hashed_password: :string
- confirmed_at: :naive_datetime
- profile_pic: :string
- name: :string
- instagram_token: :map
- facebook_token: :map
- pinterest_token: :map
- timestamps: timestamps

### Relationships

- has_one recipes -> Mehungry.Food.Recipe
- has_one user_profile -> Mehungry.Accounts.UserProfile


## Mehungry.Accounts.UserCategoryRule

**Table:** `user_category_rules`

### Fields

- user_id: :id
- delete: :boolean
- timestamps: timestamps

### Relationships

- belongs_to user_profile -> UserProfile
- belongs_to category -> Mehungry.Food.Category
- belongs_to food_restriction_type -> Mehungry.Food.FoodRestrictionType


## Mehungry.Accounts.UserFollow

**Table:** `user_follows`

### Fields

- timestamps: timestamps

### Relationships

- belongs_to user -> User
- belongs_to follow -> User


## Mehungry.Accounts.UserIngredientRule

**Table:** `user_ingredient_rules`

### Fields

- user_id: :id
- ingredient_id: :id
- food_restriction_type_id: :id
- delete: :boolean
- timestamps: timestamps

### Relationships

- belongs_to user_profile -> UserProfile


## Mehungry.Accounts.UserPost

**Table:** `user_posts`

### Fields

- timestamps: timestamps

### Relationships

- belongs_to user -> User
- belongs_to post -> Post


## Mehungry.Accounts.UserProfile

**Table:** `user_profiles`

### Fields

- alias: :string
- intro: :string
- onboarding_level: :integer
- language_preference: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User
- has_many user_category_rules -> Mehungry.Accounts.UserCategoryRule
- has_many user_ingredient_rules -> Mehungry.Accounts.UserIngredientRule


## Mehungry.Accounts.UserRecipe

**Table:** `user_recipes`

### Fields

- timestamps: timestamps

### Relationships

- belongs_to user -> User
- belongs_to recipe -> Recipe


## Mehungry.Accounts.UserToken

**Table:** `users_tokens`

### Fields

- token: :binary
- context: :string
- sent_to: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Feedback.Feedback

**Table:** `feedbacks`

### Fields

- message: :string
- email: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Food.Annotation

**Table:** `annotations`

### Fields

- at: :integer
- body: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe


## Mehungry.Food.Category

**Table:** `categories`

### Fields

- name: :string
- description: :string
- timestamps: timestamps

### Relationships

- has_many category_translation -> CategoryTranslation


## Mehungry.Food.CategoryTranslation

**Table:** `category_translations`

### Fields

- name: :string
- timestamps: timestamps

### Relationships

- belongs_to category -> Mehungry.Food.Category
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.Food.FoodRestrictionType

**Table:** `food_restriction_types`

### Fields

- alias: :string
- title: :string
- timestamps: timestamps

### Relationships

_none_


## Mehungry.Food.Ingredient

**Table:** `ingredients`

### Fields

- description: :string
- name: :string
- url: :string
- search_name: :string
- food_class: :string
- nutrient_conversion_factors: {:array, :map}
- publication_date: :string
- nutrient_data_source: :string
- timestamps: timestamps

### Relationships

- belongs_to category -> Mehungry.Food.Category
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit
- has_many ingredient_portions -> IngredientPortion
- has_many ingredient_nutrients -> IngredientNutrient
- has_many ingredient_translation -> Mehungry.Food.IngredientTranslation


## Mehungry.Food.IngredientNutrient

**Table:** `ingredient_nutrients`

### Fields

- median: :float
- amount: :float
- data_points: :integer
- type_: :string
- timestamps: timestamps

### Relationships

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to nutrient -> Mehungry.Food.Nutrient


## Mehungry.Food.IngredientPortion

**Table:** `ingredient_portions`

### Fields

- amount: :float
- value: :float
- gram_weight: :float
- reference_id: :integer
- min_year_acquired: :integer
- sequence_number: :integer
- timestamps: timestamps

### Relationships

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.IngredientTranslation

**Table:** `ingredient_translations`

### Fields

- name: :string
- description: :string
- url: :string
- timestamps: timestamps

### Relationships

- belongs_to ingredient -> Mehungry.Food.Ingredient
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.Food.Like

**Table:** `likes`

### Fields

- at: :integer
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe


## Mehungry.Food.MeasurementUnit

**Table:** `measurement_units`

### Fields

- name: :string
- alternate_name: :string
- url: :string
- timestamps: timestamps

### Relationships

- has_many ingredient_portions -> Mehungry.Food.IngredientPortion
- has_many translation -> MeasurementUnitTranslation


## Mehungry.Food.MeasurementUnitTranslation

**Table:** `measurement_unit_translations`

### Fields

- name: :string
- alternate_name: :string
- timestamps: timestamps

### Relationships

- belongs_to language -> Mehungry.Languages.Language
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.Nutrient

**Table:** `nutrients`

### Fields

- name: :string
- description: :string
- alternate_name: :string
- family: :string
- rank: :integer
- number: :string
- reference_id: :integer
- timestamps: timestamps

### Relationships

- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.Food.Recipe

**Table:** `recipes`

### Fields

- author: :string
- cooking_time_lower_limit: :integer
- cooking_time_upper_limit: :integer
- cousine: :string
- description: :string
- list_image_url: :string
- image_url: :string
- detail_image_url: :string
- recipe_image_remote: :string
- original_url: :string
- preperation_time_lower_limit: :integer
- preperation_time_upper_limit: :integer
- primary_nutrients_size: :integer
- servings: :integer
- private: :boolean
- title: :string
- difficulty: :integer
- nutrients: :map
- ingredient_interactions: {:array, :map}
- timestamps: timestamps

### Relationships

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

**Table:** `recipe_hashtags`

### Fields

- temp_id: :string

### Relationships

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to hashtag -> Mehungry.Hashtag


## Mehungry.Food.RecipeIngredient

**Table:** `recipe_ingredients`

### Fields

- quantity: :float
- ingredient_allias: :string
- delete: :boolean
- temp_id: :string
- timestamps: timestamps

### Relationships

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit
- belongs_to ingredient -> Mehungry.Food.Ingredient


## Mehungry.FoodProducts.FoodProduct

**Table:** `food_products`

### Fields

- barcode: :string
- name: :string
- brands: :string
- quantity: :string
- countries: {:array, :string}
- categories_tags: {:array, :string}
- nutriments: :map
- image_url: :string
- image_small_url: :string
- nutriscore_grade: :string
- ecoscore_grade: :string
- completeness: :float
- off_last_modified_t: :integer
- data_source: :string
- ingredient_match_score: :float
- ingredient_match_status: :string
- timestamps: timestamps

### Relationships

- belongs_to ingredient -> Mehungry.Food.Ingredient
- has_many translations -> Mehungry.FoodProducts.FoodProductTranslation


## Mehungry.FoodProducts.FoodProductTranslation

**Table:** `food_product_translations`

### Fields

- name: :string
- ingredients_text: :string
- timestamps: timestamps

### Relationships

- belongs_to food_product -> Mehungry.FoodProducts.FoodProduct
- belongs_to language -> Mehungry.Languages.Language


## Mehungry.FoodProducts.SyncState

**Table:** `off_sync_state`

### Fields

- key: :string
- last_processed_file: :string
- last_synced_at: :utc_datetime
- products_upserted: :integer
- timestamps: timestamps

### Relationships

_none_


## Mehungry.Hashtag

**Table:** `hashtags`

### Fields

- title: :string

### Relationships

- has_many recipe_hashtags -> Mehungry.Food.RecipeHashtag


## Mehungry.History.ConsumeRecipeUserMeal

**Table:** `history_consume_recipe_user_meals`

### Fields

- start_dt: :naive_datetime
- end_dt: :naive_datetime
- consume_portions: :integer
- delete: :boolean

### Relationships

- belongs_to recipe_user_meal -> RecipeUserMeal
- belongs_to user_meal -> UserMeal


## Mehungry.History.IngredientUserMeal

**Table:** `history_ingredient_user_meals`

### Fields

- quantity: :float

### Relationships

- belongs_to ingredient -> Ingredient
- belongs_to user_meal -> UserMeal
- belongs_to measurement_unit -> Mehungry.Food.MeasurementUnit


## Mehungry.History.RecipeUserMeal

**Table:** `history_recipe_user_meals`

### Fields

- consume_portions: :integer
- cooking: :boolean
- cooking_portions: :integer
- delete: :boolean

### Relationships

- belongs_to recipe -> Recipe
- belongs_to user_meal -> UserMeal
- has_many consume_recipe_user_meals -> ConsumeRecipeUserMeal


## Mehungry.History.UserMeal

**Table:** `history_user_meals`

### Fields

- start_dt: :naive_datetime
- end_dt: :naive_datetime
- title: :string
- user_id: :id
- timestamps: timestamps

### Relationships

- has_many recipe_user_meals -> RecipeUserMeal
- has_many ingredient_user_meals -> IngredientUserMeal
- has_many consume_recipe_user_meals -> ConsumeRecipeUserMeal


## Mehungry.Inventory.BasketIngredient

**Table:** `basket_ingredients`

### Fields

- quantity: :float
- in_storage: :boolean
- timestamps: timestamps

### Relationships

- belongs_to measurement_unit -> MeasurementUnit
- belongs_to ingredient -> Ingredient
- belongs_to shopping_basket -> ShoppingBasket


## Mehungry.Inventory.BasketItem

**Table:** `basket_items`

### Fields

- quantity: :float
- in_storage: :boolean
- name: :string
- nutrition_data: :map
- usda_fdc_id: :integer
- timestamps: timestamps

### Relationships

- belongs_to measurement_unit -> MeasurementUnit
- belongs_to shopping_basket -> ShoppingBasket
- belongs_to recipe -> Recipe


## Mehungry.Inventory.ShoppingBasket

**Table:** `shopping_baskets`

### Fields

- end_dt: :naive_datetime
- start_dt: :naive_datetime
- title: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> User
- has_many basket_ingredients -> BasketIngredient
- has_many basket_items -> BasketItem


## Mehungry.Languages.Language

**Table:** `languages`

### Fields

- timestamps: timestamps

### Relationships

_none_


## Mehungry.Meta.Visit

**Table:** `visits`

### Fields

- details: :map
- ip_address: :string
- session_key: :string
- timestamps: timestamps

### Relationships

_none_


## Mehungry.Plans.DailyMealPlan

**Table:** `daily_meal_plans`

### Fields

- daily_meal_plan_title: :string
- increasing_number: :integer
- meal_note: :string
- timestamps: timestamps

### Relationships

- has_many meals -> Meal
- belongs_to meal_plan -> MealPlan


## Mehungry.Plans.Meal

**Table:** `meals`

### Fields

- meal_note: :string
- meal_title: :string
- timestamps: timestamps

### Relationships

- belongs_to recipe -> Recipe
- belongs_to daily_meal_plan -> DailyMealPlan


## Mehungry.Plans.MealPlan

**Table:** `meal_plans`

### Fields

- description: :string
- title: :string
- user_id: :id
- timestamps: timestamps

### Relationships

- has_many daily_meal_plans -> DailyMealPlan


## Mehungry.Posts.Comment

**Table:** `comments`

### Fields

- text: :string
- timestamps: timestamps

### Relationships

- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to user -> Mehungry.Accounts.User
- belongs_to post -> Mehungry.Posts.Post
- has_many comment_answers -> Mehungry.Posts.CommentAnswer
- has_many votes -> Mehungry.Posts.CommentVote


## Mehungry.Posts.CommentAnswer

**Table:** `comment_answers`

### Fields

- text: :string
- timestamps: timestamps

### Relationships

- belongs_to comment -> Mehungry.Posts.Comment
- belongs_to user -> Mehungry.Accounts.User
- has_many votes -> Mehungry.Posts.CommentAnswerVote


## Mehungry.Posts.CommentAnswerVote

**Table:** `comment_answer_votes`

### Fields

- positive: :boolean
- timestamps: timestamps

### Relationships

- belongs_to comment_answer -> Mehungry.Posts.CommentAnswer
- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Posts.CommentVote

**Table:** `comment_votes`

### Fields

- positive: :boolean
- timestamps: timestamps

### Relationships

- belongs_to comment -> Mehungry.Posts.Comment
- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Posts.Post

**Table:** `posts`

### Fields

- bg_media_url: :string
- description: :string
- md_media_url: :string
- reference_url: :string
- sm_media_url: :string
- title: :string
- type_: :string
- language_name: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User
- belongs_to recipe -> Mehungry.Food.Recipe
- belongs_to reference -> Mehungry.Food.Recipe
- has_many comments -> Comment
- has_many upvotes -> PostUpvote
- has_many downvotes -> PostDownvote


## Mehungry.Posts.PostDownvote

**Table:** `post_downvotes`

### Fields

- post_id: :id
- user_id: :id
- timestamps: timestamps

### Relationships

_none_


## Mehungry.Posts.PostUpvote

**Table:** `post_upvotes`

### Fields

- post_id: :id
- user_id: :id
- timestamps: timestamps

### Relationships

_none_


## Mehungry.Professionals.Appointment

**Table:** `professional_appointments`

### Fields

- scheduled_at: :naive_datetime
- ends_at: :naive_datetime
- title: :string
- notes: :string
- external_client_name: :string
- timestamps: timestamps

### Relationships

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Professionals.MealPlanRating

**Table:** `meal_plan_ratings`

### Fields

- rating_type: :string
- score: :integer
- comment: :string
- rated_for_date: :date
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User
- belongs_to daily_meal_plan -> Mehungry.Plans.DailyMealPlan
- belongs_to meal_plan -> Mehungry.Plans.MealPlan


## Mehungry.Professionals.ProfessionalProfile

**Table:** `professional_profiles`

### Fields

- specialization: :string
- bio: :string
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Professionals.TutorClientAssignment

**Table:** `tutor_client_assignments`

### Fields

- timestamps: timestamps

### Relationships

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Professionals.TutorInvitation

**Table:** `tutor_invitations`

### Fields

- status: :string
- message: :string
- timestamps: timestamps

### Relationships

- belongs_to professional -> Mehungry.Accounts.User
- belongs_to client -> Mehungry.Accounts.User


## Mehungry.Subscriptions.AiUsage

**Table:** `ai_usage`

### Fields

- feature: :string
- used_at: :naive_datetime
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Subscriptions.UserSubscription

**Table:** `user_subscriptions`

### Fields

- tier: :string
- status: :string
- stripe_customer_id: :string
- stripe_subscription_id: :string
- period_start: :naive_datetime
- period_end: :naive_datetime
- timestamps: timestamps

### Relationships

- belongs_to user -> Mehungry.Accounts.User


## Mehungry.Telemetry.ErrorEvent

**Table:** `error_events`

### Fields

- fingerprint: :string
- kind: :string
- source: :string
- reason: :string
- stacktrace: :string
- context: :map
- count: :integer
- first_seen: :utc_datetime
- last_seen: :utc_datetime

### Relationships

_none_


## Mehungry.Telemetry.QueryProfile

**Table:** `query_time_profiles`

### Fields

- fingerprint: :string
- query: :string
- source: :string
- period_start: :utc_datetime
- min: :float
- avg: :float
- max: :float
- p95: :float
- sample_count: :integer

### Relationships

_none_


## Mehungry.Telemetry.Snapshot

**Table:** `telemetry_snapshots`

### Fields

- metric: :string
- tags: :map
- period_start: :utc_datetime
- min: :float
- avg: :float
- max: :float
- p95: :float
- sample_count: :integer

### Relationships

_none_
