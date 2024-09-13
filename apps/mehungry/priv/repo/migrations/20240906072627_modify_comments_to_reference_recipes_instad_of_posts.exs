defmodule Mehungry.Repo.Migrations.ModifyCommentsToReferenceRecipesInstadOfPosts do
  use Ecto.Migration

  def up do
    alter table(:comments) do
      add :recipe_id, references(:recipes, on_delete: :delete_all)
    end

    flush()
    repo = repo()

    comments =
      repo.all(Mehungry.Posts.Comment)
      |> repo.preload(:post)

    Enum.each(comments, fn x ->
      changeset = Mehungry.Posts.Comment.changeset(x, %{recipe_id: x.post.reference_id})
      repo.update(changeset)
    end)

    alter table(:comments) do
      remove(:post_id)
    end
  end

  def down do
    alter table(:comments) do
      remove(:recipe_id)
      add :post_id, references(:posts, on_delete: :delete_all)
    end
  end
end
