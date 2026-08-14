# Hashtag

Table `hashtags` · Schema `Mehungry.Hashtag` (`lib/mehungry/hashtag.ex`).
Index: [`entities.md`](entities.md).

A reusable topic tag applied to recipes.

## Fields

| Field | Type | Notes |
|---|---|---|
| `title` | string | the tag text |

## Relationships

- `has_many :recipe_hashtags` — the [Recipe](recipe.md) ↔ hashtag join (`recipe_hashtags`,
  virtual `temp_id`). `Recipe.changeset/2` reuses an existing tag by title via
  `get_hashtags/1`; see [Recipe → Hashtags](recipe.md#hashtags).

## Notes

- Lookup helper `Mehungry.Hashtag.get_hashtag_by_title/1`.

## Referenced by

[`recipe.md`](recipe.md)
