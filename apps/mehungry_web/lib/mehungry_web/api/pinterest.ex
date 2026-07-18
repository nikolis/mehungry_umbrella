defmodule Mehungry.Api.Pinterest do
  @moduledoc """
  Pinterest v5 API client.
  Handles board listing and pin creation for connected user accounts.
  """

  require Logger

  alias Mehungry.Food.Recipe

  # TEMPORARY: pointed at the Pinterest sandbox for demo purposes.
  # Restore to "https://api.pinterest.com/v5" after the demo.
  @api_base "https://api-sandbox.pinterest.com/v5"

  use MehungryWeb, :verified_routes

  @doc """
  Returns the user's Pinterest boards. Returns [] if no token is connected
  or if the API call fails.
  """
  def get_boards(user) do
    case access_token(user) do
      nil ->
        Logger.warning("[Pinterest] get_boards: no access token for user #{user.id}")
        []

      token ->
        url = "#{@api_base}/boards?page_size=25"

        case HTTPoison.get(url, [{"Authorization", "Bearer #{token}"}]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"items" => boards}} ->
                Logger.info(
                  "[Pinterest] get_boards: #{length(boards)} boards for user #{user.id}"
                )

                boards

              {:ok, other} ->
                Logger.warning(
                  "[Pinterest] get_boards: unexpected response shape: #{inspect(other)}"
                )

                []

              {:error, err} ->
                Logger.warning("[Pinterest] get_boards: JSON decode error: #{inspect(err)}")
                []
            end

          {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
            Logger.warning("[Pinterest] get_boards: HTTP #{status} — #{body}")
            []

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.warning("[Pinterest] get_boards: request error — #{inspect(reason)}")
            []
        end
    end
  end

  @doc """
  Creates a Pinterest pin for the given recipe on the specified board.
  Returns {:ok, pin_map} or {:error, reason}.
  """
  def create_pin(user, %Recipe{} = recipe, board_id) do
    with token when not is_nil(token) <- access_token(user),
         {:ok, body} <- build_pin_body(recipe, board_id) do
      case HTTPoison.post(
             "#{@api_base}/pins",
             body,
             [
               {"Authorization", "Bearer #{token}"},
               {"Content-Type", "application/json"}
             ]
           ) do
        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
        when status in 200..299 ->
          Logger.info(
            "[Pinterest] create_pin: pin created for user #{user.id} on board #{board_id} (recipe #{recipe.id})"
          )

          case Jason.decode(resp_body) do
            {:ok, pin} -> {:ok, pin}
            _ -> {:ok, %{}}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
          Logger.warning(
            "[Pinterest] create_pin: HTTP #{status} for user #{user.id} board #{board_id} (recipe #{recipe.id}) — #{resp_body}"
          )

          {:error, "Pinterest API returned #{status}: #{resp_body}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error(
            "[Pinterest] create_pin: request error for user #{user.id} board #{board_id} (recipe #{recipe.id}) — #{inspect(reason)}"
          )

          {:error, inspect(reason)}
      end
    else
      nil ->
        Logger.warning(
          "[Pinterest] create_pin: no access token for user #{user.id} (recipe #{recipe.id})"
        )

        {:error, "No Pinterest account connected"}

      {:error, reason} ->
        Logger.error(
          "[Pinterest] create_pin: could not build pin body for user #{user.id} (recipe #{recipe.id}) — #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Creates a Pinterest board for the user.
  Accepts a map with "name" (required), "description" and "privacy" (optional).
  Returns {:ok, board_map} or {:error, reason}.
  """
  def create_board(user, attrs) do
    case access_token(user) do
      nil ->
        Logger.warning("[Pinterest] create_board: no access token for user #{user.id}")
        {:error, "No Pinterest account connected"}

      token ->
        body =
          %{
            "name" => attrs["name"],
            "privacy" => attrs["privacy"] || "PUBLIC"
          }
          |> maybe_put_description(attrs["description"])
          |> Jason.encode!()

        case HTTPoison.post(
               "#{@api_base}/boards",
               body,
               [
                 {"Authorization", "Bearer #{token}"},
                 {"Content-Type", "application/json"}
               ]
             ) do
          {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
          when status in 200..299 ->
            Logger.info("[Pinterest] create_board: board created for user #{user.id}")

            case Jason.decode(resp_body) do
              {:ok, board} -> {:ok, board}
              _ -> {:ok, %{}}
            end

          {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
            Logger.warning(
              "[Pinterest] create_board: HTTP #{status} for user #{user.id} — #{resp_body}"
            )

            {:error, "Pinterest API returned #{status}: #{resp_body}"}

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error(
              "[Pinterest] create_board: request error for user #{user.id} — #{inspect(reason)}"
            )

            {:error, inspect(reason)}
        end
    end
  end

  defp maybe_put_description(body, nil), do: body
  defp maybe_put_description(body, ""), do: body
  defp maybe_put_description(body, description), do: Map.put(body, "description", description)

  defp build_pin_body(%Recipe{} = recipe, board_id) do
    pin = %{
      board_id: board_id,
      title: recipe.title,
      description: build_description(recipe),
      link: MehungryWeb.Endpoint.url() <> ~p"/browse/#{recipe.id}",
      media_source: %{
        source_type: "image_url",
        url: recipe.image_url || ""
      }
    }

    case Jason.encode(pin) do
      {:ok, json} -> {:ok, json}
      err -> err
    end
  end

  defp build_description(%Recipe{} = recipe) do
    base = recipe.description || recipe.title

    cooking_time =
      case recipe.cooking_time_lower_limit do
        nil -> ""
        t -> " · #{t} min"
      end

    String.slice(base <> cooking_time <> " #mehungry", 0, 500)
  end

  defp access_token(user) do
    case Map.get(user.pinterest_token || %{}, "access_token") do
      nil ->
        nil

      "" ->
        nil

      # OAuth2 library stored the raw JSON body instead of just the token
      # when Accept: application/json was missing. Unwrap it transparently.
      val ->
        case Jason.decode(val) do
          {:ok, %{"access_token" => inner}} -> inner
          _ -> val
        end
    end
  end
end
