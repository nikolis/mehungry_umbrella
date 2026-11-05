defmodule MehungryWeb.CreateRecipeImageUploadTest do
  use MehungryWeb.ConnCase

  alias Mehungry.FoodData.Usda.SeedFileParser
  alias Mehungry.Food

  import Phoenix.LiveViewTest

  # Stub storage backend so the external presign path doesn't hit Supabase.
  defmodule FakeStorage do
    def signed_upload(key, _opts) do
      {:ok,
       %{
         method: "PUT",
         url: "https://fake.supabase.co/storage/v1/object/upload/sign/bucket/#{key}",
         headers: %{},
         key: key,
         public_url:
           "https://fake.supabase.co/storage/v1/object/public/bucket/#{key}"
       }}
    end

    def public_url(key), do: "https://fake.supabase.co/storage/v1/object/public/bucket/#{key}"
    def delete(_key), do: {:ok, :deleted}
    def delete_by_url(_url), do: {:ok, :deleted}
  end

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, :auto)

    SeedFileParser.get_ingredients_from_food_data_central_json_file(
      "test/foundationDownload.json"
    )

    :ok
  end

  setup do
    prev_storage = Application.get_env(:mehungry, :storage)
    prev_impl = Application.get_env(:mehungry, :storage_impl)
    Application.put_env(:mehungry, :storage, backend: :supabase)
    Application.put_env(:mehungry, :storage_impl, FakeStorage)

    on_exit(fn ->
      if prev_storage, do: Application.put_env(:mehungry, :storage, prev_storage),
        else: Application.delete_env(:mehungry, :storage)

      if prev_impl, do: Application.put_env(:mehungry, :storage_impl, prev_impl),
        else: Application.delete_env(:mehungry, :storage_impl)
    end)

    :ok
  end

  @create_params_recipe %{
    servings: 3,
    title: "Image Edit Recipe",
    language_name: "En",
    difficulty: "1",
    cooking_time_lower_limit: 5,
    preperation_time_lower_limit: 5
  }

  describe "Edit recipe with a new image" do
    setup [:register_and_log_in_user]

    test "uploading a new image on edit saves without crashing", %{conn: conn, user: user} do
      [ingredient | _] = Food.search_ingredient("beans", nil)
      [gram] = Food.search_measurement_unit("gram")

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 500}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)

      {:ok, index_live, _html} =
        live(conn, Routes.create_recipe_index_path(conn, :edit, recipe.id))

      # The recipe already has an image, so the uploader is hidden until the
      # existing image is removed — this is the real "replace image" flow.
      render_click(index_live, "delete-image")

      image =
        file_input(index_live, ".the_form", :image, [
          %{
            name: "new.jpg",
            content: String.duplicate("a", 100),
            type: "image/jpeg"
          }
        ])

      assert render_upload(image, "new.jpg") =~ "100"

      ingredients = %{
        0 => %{
          ingredient_id: ingredient.id,
          measurement_unit_id: gram.id,
          quantity: 500
        }
      }

      {:ok, _view, _html} =
        index_live
        |> form(".the_form", recipe: @create_params_recipe)
        |> render_submit(%{recipe: %{"recipe_ingredients" => ingredients}})
        |> follow_redirect(conn, Routes.profile_index_path(conn, :index))

      updated = Food.get_recipe!(recipe.id)
      assert updated.image_url =~ "fake.supabase.co"
    end
  end
end
