defmodule Mehungry.Api.Facebook do
  alias Mehungry.Accounts
  alias Mehungry.Food.Recipe

  @api_base "https://graph.facebook.com/"
  @api_version "v21.0"

  defp get_recipe_caption(%Recipe{} = recipe) do
    recipe.title <>
      " \n " <>
      recipe.description <>
      " \n \n \n " <>
      get_recipe_ingredients_text(recipe) <>
      " \n " <>
      get_recipe_instructions_text(recipe) <>
      " \n " <> get_recipe_nutrients_text(recipe) <> " \n \n " <> "#m3hungry"
  end

  defp get_recipe_ingredients_text(recipe) do
    Enum.reduce(recipe.recipe_ingredients, " Ingredients \n \n", fn x, acc ->
      acc <>
        Float.to_string(x.quantity) <>
        " " <> x.measurement_unit.name <> "  " <> x.ingredient.name <> " \n "
    end)
  end

  defp get_recipe_nutrients_text(recipe) do
    Enum.map(recipe.nutrients, fn {_, whole} ->
      whole["name"] <>
        " " <>
        Float.to_string(Float.round(whole["amount"], 2)) <>
        " " <>
        whole["measurement_unit"]
    end)
    |> Enum.reduce("Nutrients \n ", fn x, acc ->
      acc <> " \n " <> x
    end)
  end

  defp get_recipe_instructions_text(recipe) do
    if Enum.empty?(recipe.steps) do
      ""
    else
      Enum.reduce(recipe.steps, " Instructions \n ", fn x, acc ->
        acc <> " " <> x.title <> " \n " <> x.description <> " \n "
      end)
    end
  end

  @doc """
  Access the graph endpoint to exchange short_lived token for long_lived token the short_lived token should not be expired
  """
  def get_user_pages(user, token, facebook_user_id) do
    # token = Accounts.get_user_token(user, "facebook")

    "https://graph.facebook.com/v21.0/user_id/accounts?access_token=user_access_token"

    url =
      @api_base <>
        @api_version <> "/" <> facebook_user_id <> "/" <> "accounts" <> "?access_token=#{token}"

    {:ok, get_response} =
      HTTPoison.get(url)

    {:ok, decoded_body} = Jason.decode(get_response.body)

    data =
      Enum.reduce(decoded_body["data"], %{}, fn page_entry, acc ->
        result = %{page_entry["name"] => page_entry}
        result = Enum.into(result, acc)
        result
      end)

    result = Mehungry.Accounts.update_user_tokens(user, %{"facebook_token" => data})
    IO.inspect(result, label: "Saved tokesn")
  end

  defp construct_url(path, params) do
    path <> params
  end

  def post_recipe_container(user, recipe, page) do
    user_id = Map.get(page, "id", "")
    access_token = Map.get(page, "access_token", "")

    # caption = get_recipe_caption(recipe)

    headers = [
      Authorization: "Bearer #{access_token}",
      Accept: "Application/json; Charset=utf-8",
      image_url: recipe.image_url
    ]

    {:ok, body} =
      Jason.encode(%{
        link: "https://www.m3hungry.com/browse/" <> Integer.to_string(recipe.id),
        message: "Some publish message",
        published: true
      })

    HTTPoison.post!(
      @api_base <>
        "/" <>
        @api_version <>
        "/" <> user_id <> "/feed",
      body,
      headers,
      params: %{
        link: "https://www.m3hungry.com/browse/11",
        message: "Some publish message",
        published: true
      }
    )
  end

  def publish_recipe_container(user, code) do
    token = Accounts.get_user_tokens(user, "instagram")

    token = Jason.decode!(token)
    user_id = Map.get(token, "user_id", "")
    access_token = Map.get(token, "access_token", "")
    headers = [Authorization: "Bearer #{access_token}", Accept: "Application/json; Charset=utf-8"]

    HTTPoison.post(
      @api_base <>
        "/" <>
        @api_version <>
        "/" <> Integer.to_string(user_id) <> "/media_publish",
      "{\"creation_id\" = " <> code <> "}",
      headers,
      params: %{creation_id: code}
    )
  end
end
