defmodule Mehungry.Repo.Migrations.AddRecipeTranslationsToSearch do
  use Ecto.Migration

  def up do
    # Drop existing triggers that refresh the view
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipes")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipe_ingredients")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON ingredient_translations")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipe_translations")

    execute("DROP FUNCTION IF EXISTS refresh_recipe_search")
    execute("DROP MATERIALIZED VIEW IF EXISTS recipe_search")

    execute("""
    CREATE MATERIALIZED VIEW recipe_search AS
    SELECT
      recipes.id AS id,
      recipes.title AS title,
      (
      setweight(to_tsvector(unaccent(coalesce(recipes.title, ''))), 'A') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(DISTINCT recipe_translations.title, ' '), ' '))), 'A') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(DISTINCT ingredients.name, ' '), ' '))), 'B') ||
      setweight(to_tsvector(unaccent(coalesce(string_agg(DISTINCT ingredient_translations.name, ' '), ' '))), 'C')
      ) AS document
    FROM recipes
    LEFT JOIN recipe_translations ON recipe_translations.recipe_id = recipes.id
    LEFT JOIN recipe_ingredients ON recipe_ingredients.recipe_id = recipes.id
    LEFT JOIN ingredients ON ingredients.id = recipe_ingredients.ingredient_id
    LEFT JOIN ingredient_translations ON ingredient_translations.ingredient_id = ingredients.id
    GROUP BY recipes.id
    """)

    create index("recipe_search", ["document"], using: :gin)

    execute(
      "CREATE INDEX recipe_search_title_trgm_index ON recipe_search USING gin (title gin_trgm_ops)"
    )

    create unique_index("recipe_search", [:id])

    execute("""
    CREATE OR REPLACE FUNCTION refresh_recipe_search()
    RETURNS TRIGGER LANGUAGE plpgsql
    AS $$
    BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY recipe_search;
    RETURN NULL;
    END $$;
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON recipes
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON recipe_ingredients
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON ingredient_translations
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON recipe_translations
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipes")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipe_ingredients")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON ingredient_translations")
    execute("DROP TRIGGER IF EXISTS refresh_recipe_search ON recipe_translations")
    execute("DROP FUNCTION IF EXISTS refresh_recipe_search")
    execute("DROP MATERIALIZED VIEW IF EXISTS recipe_search")

    execute("""
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
    """)

    create index("recipe_search", ["document"], using: :gin)

    execute(
      "CREATE INDEX recipe_search_title_trgm_index ON recipe_search USING gin (title gin_trgm_ops)"
    )

    create unique_index("recipe_search", [:id])

    execute("""
    CREATE OR REPLACE FUNCTION refresh_recipe_search()
    RETURNS TRIGGER LANGUAGE plpgsql
    AS $$
    BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY recipe_search;
    RETURN NULL;
    END $$;
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON recipes
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON recipe_ingredients
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)

    execute("""
    CREATE TRIGGER refresh_recipe_search
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
    ON ingredient_translations
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_recipe_search();
    """)
  end
end
