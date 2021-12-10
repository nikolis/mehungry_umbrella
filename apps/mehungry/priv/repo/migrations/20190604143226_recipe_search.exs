defmodule MehungryServer.Repo.Migrations.RecipeSearch do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE EXTENSION IF NOT EXISTS unaccent
      """
    )
    execute(
      """
      CREATE EXTENSION IF NOT EXISTS pg_trgm
      """
    )
 
   execute(
      """
      CREATE MATERIALIZED VIEW recipe_search AS
      SELECT
        recipes.id AS id,
        recipes.title AS title,
        (
        setweight(to_tsvector(unaccent(recipes.title)), 'A') ||
        setweight(to_tsvector(unaccent(coalesce(string_agg(ingredients.name, ' '), ' '))), 'B') ||
        setweight(to_tsvector(unaccent(coalesce(string_agg(ingredient_translations.name, ' '), ' '))), 'C')

        ) AS document
      FROM recipes
      LEFT JOIN recipe_ingredients ON recipe_ingredients.recipe_id = recipes.id
      LEFT JOIN ingredients ON ingredients.id = recipe_ingredients.ingredient_id
      LEFT JOIN ingredient_translations ON ingredient_translations.ingredient_id = ingredients.id
      GROUP BY recipes.id
      """
    )

    # to support full-text searches
    create index("recipe_search", ["document"], using: :gin)

    # to support substring title matches with ILIKE
    execute("CREATE INDEX recipe_search_title_trgm_index ON recipe_search USING gin (title gin_trgm_ops)")

    # to support updating CONCURRENTLY
    create unique_index("recipe_search", [:id])

    execute(
      """
      CREATE OR REPLACE FUNCTION refresh_recipe_search()
      RETURNS TRIGGER LANGUAGE plpgsql
      AS $$
      BEGIN
      REFRESH MATERIALIZED VIEW CONCURRENTLY recipe_search;
      RETURN NULL;
      END $$;
      """
    )


    execute(
      """
      CREATE TRIGGER refresh_recipe_search
      AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
      ON recipes
      FOR EACH STATEMENT
      EXECUTE PROCEDURE refresh_recipe_search();
      """
    )

    execute(
      """
      CREATE TRIGGER refresh_recipe_search
      AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
      ON recipe_ingredients
      FOR EACH STATEMENT
      EXECUTE PROCEDURE refresh_recipe_search();
      """
    )

    execute(
      """
      CREATE TRIGGER refresh_recipe_search
      AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
      ON ingredient_translations
      FOR EACH STATEMENT
      EXECUTE PROCEDURE refresh_recipe_search();
      """
    )

  end
end
