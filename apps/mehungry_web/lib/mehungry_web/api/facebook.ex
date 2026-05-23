defmodule Mehungry.Api.Facebook do
  alias Mehungry.Accounts
  alias Mehungry.Food.Recipe

  @api_base "https://graph.facebook.com/"
  @api_version "v21.0"

  @priority_nutrients [
    "Energy",
    "Protein",
    "Total Fat",
    "Total Carbohydrate",
    "Carbohydrate",
    "Dietary Fiber",
    "Fiber",
    "Sodium"
  ]

  @doc """
  Exchange a short-lived Facebook token for a long-lived one and fetch page list.
  """
  def get_user_pages(user, token, facebook_user_id) do
    url =
      @api_base <>
        @api_version <> "/" <> facebook_user_id <> "/accounts?access_token=#{token}"

    {:ok, response} = HTTPoison.get(url)
    {:ok, decoded} = Jason.decode(response.body)

    pages =
      Enum.reduce(decoded["data"] || [], %{}, fn page, acc ->
        Map.put(acc, page["name"], page)
      end)

    Mehungry.Accounts.update_user_tokens(user, %{"facebook_token" => pages})
  end

  @doc """
  Post the recipe as a photo to the given Facebook page.
  Uses recipe.image_url as the photo and a formatted caption with
  ingredients and key nutrients.
  """
  def post_recipe_container(_user, recipe, page) do
    user_id = Map.get(page, "id", "")
    access_token = Map.get(page, "access_token", "")
    caption = build_caption(recipe)

    HTTPoison.post!(
      @api_base <> @api_version <> "/" <> user_id <> "/photos",
      "",
      [{"Accept", "application/json"}],
      params: %{
        url: recipe.image_url,
        caption: caption,
        published: true,
        access_token: access_token
      }
    )
  end

  def publish_recipe_container(user, code) do
    token = Accounts.get_user_tokens(user, "instagram")
    token = Jason.decode!(token)
    user_id = Map.get(token, "user_id", "")
    access_token = Map.get(token, "access_token", "")

    headers = [
      Authorization: "Bearer #{access_token}",
      Accept: "Application/json; Charset=utf-8"
    ]

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

  # ---------------------------------------------------------------------------
  # Caption builder
  # ---------------------------------------------------------------------------

  defp build_caption(%Recipe{} = recipe) do
    [
      header(recipe),
      ingredients_section(recipe),
      nutrients_section(recipe),
      footer(recipe)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp header(%Recipe{title: title, description: desc}) do
    base = "🍽️  #{title}"

    if desc && String.trim(desc) != "" do
      base <> "\n" <> String.trim(desc)
    else
      base
    end
  end

  defp ingredients_section(%Recipe{recipe_ingredients: %Ecto.Association.NotLoaded{}}), do: nil
  defp ingredients_section(%Recipe{recipe_ingredients: []}), do: nil

  defp ingredients_section(%Recipe{recipe_ingredients: items, servings: servings}) do
    label =
      if servings && servings > 0,
        do: "📋  Ingredients  (#{servings} servings)",
        else: "📋  Ingredients"

    lines =
      items
      |> Enum.reject(fn ri ->
        is_struct(ri.ingredient, Ecto.Association.NotLoaded) or
          is_struct(ri.measurement_unit, Ecto.Association.NotLoaded)
      end)
      |> Enum.map(fn ri ->
        qty = format_qty(ri.quantity)
        "  • #{qty} #{ri.measurement_unit.name}  #{ri.ingredient.name}"
      end)

    if lines == [] do
      nil
    else
      label <> "\n" <> Enum.join(lines, "\n")
    end
  end

  defp nutrients_section(%Recipe{nutrients: nutrients, servings: servings})
       when is_map(nutrients) and map_size(nutrients) > 0 do
    per = if servings && servings > 0, do: servings, else: 1

    lines =
      nutrients
      |> Map.values()
      |> Enum.filter(fn n ->
        name = n["name"] || ""
        Enum.any?(@priority_nutrients, &(String.downcase(name) == String.downcase(&1)))
      end)
      |> Enum.sort_by(fn n ->
        name = n["name"] || ""
        Enum.find_index(@priority_nutrients, &(String.downcase(name) == String.downcase(&1))) || 99
      end)
      |> Enum.map(fn n ->
        name = n["name"] || ""
        amount = (n["amount"] || 0) / per
        unit = n["measurement_unit"] || "g"
        "  • #{name}: #{format_amount(amount)} #{unit}"
      end)

    if lines == [] do
      nil
    else
      "📊  Nutrition per serving\n" <> Enum.join(lines, "\n")
    end
  end

  defp nutrients_section(_), do: nil

  defp footer(%Recipe{id: id}) do
    "🔗  https://www.m3hungry.com/browse/#{id}\n#m3hungry #recipe"
  end

  defp format_qty(qty) when is_float(qty) do
    if qty == Float.round(qty, 0), do: trunc(qty) |> to_string(), else: Float.round(qty, 1) |> to_string()
  end

  defp format_qty(qty), do: to_string(qty)

  defp format_amount(amount) when is_float(amount) do
    cond do
      amount >= 100 -> trunc(Float.round(amount, 0)) |> to_string()
      amount >= 10 -> Float.round(amount, 1) |> to_string()
      amount >= 1 -> Float.round(amount, 2) |> to_string()
      true -> Float.round(amount, 3) |> to_string()
    end
  end

  defp format_amount(amount), do: to_string(amount)
end
