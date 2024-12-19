defmodule Mehungry.Api.Facebook do
  alias Mehungry.Accounts
  alias Mehungry.Food.Recipe

  @api_base "https://graph.instagram.com"
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
  def get_long_lived_token(user, existing_token, instagram_user_id) do
    # Application.fetch_env(:mehungry, :INSTAGRAM_CLIENT_SECRET)
    instagram_secret = System.get_env("INSTAGRAM_CLIENT_SECRET")

    {:ok, get_response} =
      HTTPoison.get(
        @api_base <>
          "/" <>
          "access_token" <>
          "?grant_type=ig_exchange_token" <>
          "&client_secret=#{instagram_secret}" <>
          "&access_token=#{existing_token}"
      )

    {:ok, token} = Jason.decode(get_response.body)
    token = Map.put(token, "user_id", instagram_user_id)
    Mehungry.Accounts.update_user_tokens(user, %{"instagram_token" => token})
  end

  def post_recipe_container(user, recipe) do
    # token = Accounts.get_user_tokens(user, "instagram")
    token = user.instagram_token

    user_id = Map.get(token, "user_id", "")
    access_token = Map.get(token, "access_token", "")

    caption = get_recipe_caption(recipe)

    headers = [
      Authorization: "Bearer #{access_token}",
      Accept: "Application/json; Charset=utf-8",
      image_url: recipe.image_url
    ]

    {:ok, body} = Jason.encode(%{"image_url" => recipe.image_url})

    response_create_container =
      HTTPoison.post(
        @api_base <>
          "/" <>
          @api_version <>
          "/" <> Integer.to_string(user_id) <> "/media",
        body,
        headers,
        params: %{image_url: recipe.image_url, caption: caption}
      )

    case response_create_container do
      {:ok, %HTTPoison.Response{status_code: 200} = response} ->
        {:ok, body} = Jason.decode(response.body)
        id = body["id"]
        publish_recipe_container(user, id)

      _ ->
        nil
    end
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
      params:
        %{creation_id: code}
    )
  end
end
