defmodule MehungryWeb.ImageProcessing do
  @moduledoc false

  def resize(path, width, height, opts \\ [])

  def resize(nil, _width, _height, _opts) do
    nil
  end

  def resize(image_path, _width, _height, _opts) do
    image_name =
      image_path
      |> String.split("/")
      |> Enum.at(-1)
      |> String.split(".")
      |> Enum.at(0)

    pre_image_name = Path.join([:code.priv_dir(:mehungry_web), "static/images", image_name])
    new_image_name = image_name <> "_list.jpg"
    new_image_write = Path.join([:code.priv_dir(:mehungry_web), "static/images/", new_image_name])
    new_image_read = Path.join([MehungryWeb.Endpoint.url(), "images", new_image_name])

    case File.exists?(new_image_write) do
      false ->
        %HTTPoison.Response{body: body} = HTTPoison.get!(image_path)
        _file = File.write!(pre_image_name, body)

        {:ok, result} =
          Image.thumbnail(pre_image_name, "270x200", crop: :center, autorotate: true)

        _return = Vix.Vips.Image.write_to_file(result, new_image_write)
        new_image_read

      true ->
        new_image_read
    end
  end

  def resize_details(image_path, _width, _height, _opts \\ []) do
    image_name =
      image_path
      |> String.split("/")
      |> Enum.at(-1)
      |> String.split(".")
      |> Enum.at(0)

    pre_image_name = Path.join([:code.priv_dir(:mehungry_web), "static/images", image_name])
    new_image_name = image_name <> "_detail.jpg"
    new_image_write = Path.join([:code.priv_dir(:mehungry_web), "static/images/", new_image_name])
    new_image_read = Path.join([MehungryWeb.Endpoint.url(), "images", new_image_name])

    case File.exists?(new_image_write) do
      false ->
        %HTTPoison.Response{body: body} = HTTPoison.get!(image_path)
        _file = File.write!(pre_image_name, body)

        {:ok, result} =
          Image.thumbnail(pre_image_name, "1000x700", crop: :center, autorotate: true)

        _return = Vix.Vips.Image.write_to_file(result, new_image_write)
        new_image_read

      true ->
        new_image_read
    end
  end
end
