defmodule Mehungry.FdcFoodParserSplitter do
  defp get_json(filename) do
    File.mkdir("fdc_legacy_splited_files")
    File.cd("fdc_legacy_splited_files")
    with {:ok, body} <- File.read(filename), {:ok, json} <- Poison.decode(body), do: {:ok, json}
  end

  def get_ingredients_from_food_data_central_json_file(file_path) do
    {:ok, json_body} = get_json(file_path)
    the_ingredients = json_body["SRLegacyFoods"]
    # num_slices = ceil(length(the_ingredients)/150)
    # the_ingredients_index = Enum.with_index(the_ingredients)
    chunks = Enum.chunk_every(the_ingredients, 50)
    chunks_indexed = Enum.with_index(chunks)

    Enum.each(chunks_indexed, fn {x, ind} ->
      write_slice_to_file(x, ind)
    end)
  end

  defp write_slice_to_file(slice, index) do
    file_name = "ing_slice" <> Integer.to_string(index) <> ".json"
    File.touch(file_name)
    File.write(file_name, Poison.encode!(slice))
  end

  defp get_json_or(filename) do
    with {:ok, body} <- File.read(filename), {:ok, json} <- Poison.decode(body), do: {:ok, json}
  end

  def get_ingredients_from_files_directory(file_path) do
    all_files = Path.wildcard(file_path <> "*.json")

    Enum.each(all_files, fn x ->
      {:ok, json_body} = get_json_or(x)
      Enum.each(json_body, fn x -> Mehungry.FdcFoodParserLeg.create_ingredient(x) end)
    end)
  end
end
