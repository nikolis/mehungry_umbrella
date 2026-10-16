defmodule Mehungry.Social.Pinterest do
  @moduledoc """
  Pinterest v5 API client.
  Handles board listing, pin creation, and OAuth token refresh for connected
  user accounts.

  Access tokens are short-lived (~30 days). `refresh_user_token/1` exchanges the
  stored refresh token for a fresh access token; the daily
  `Mehungry.ObanWorkers.PinterestTokenRefreshWorker` calls it before expiry, and
  the authed API calls here additionally refresh-and-retry once on a `401` so a
  token that lapsed between cron runs recovers transparently instead of
  surfacing as "reconnect".

  The HTTP layer is resolved via the `:pinterest_http_client` app config key
  (default `HTTPoison`) so tests can stub it.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Accounts
  alias Mehungry.Accounts.User
  alias Mehungry.Food.Recipe
  alias Mehungry.Repo
  alias Mehungry.Social.Pinterest.Token

  @doc """
  Returns `{:ok, boards}` with the user's Pinterest boards, `{:error, :not_connected}`
  when no token is stored, or `{:error, {:http_error, status, body}} |
  {:error, {:transport_error, reason}}` when the API call fails (callers should
  surface a "reconnect" state rather than an empty board list).
  """
  def get_boards(user) do
    url = "#{api_base()}/boards?page_size=25"

    result =
      authed_request(user, fn token ->
        http_client().get(url, [{"Authorization", "Bearer #{token}"}])
      end)

    case result do
      {:error, :not_connected} ->
        Logger.warning("[Pinterest] get_boards: no access token for user #{user.id}")
        {:error, :not_connected}

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"items" => boards}} ->
            Logger.info("[Pinterest] get_boards: #{length(boards)} boards for user #{user.id}")
            {:ok, boards}

          {:ok, other} ->
            Logger.warning("[Pinterest] get_boards: unexpected response shape: #{inspect(other)}")
            {:error, {:http_error, 200, other}}

          {:error, err} ->
            Logger.warning("[Pinterest] get_boards: JSON decode error: #{inspect(err)}")
            {:error, {:http_error, 200, body}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.warning("[Pinterest] get_boards: HTTP #{status} — #{body}")
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warning("[Pinterest] get_boards: request error — #{inspect(reason)}")
        {:error, {:transport_error, reason}}
    end
  end

  @doc """
  Creates a Pinterest pin for the given recipe on the specified board.
  Returns {:ok, pin_map} or {:error, reason}.
  """
  def create_pin(user, %Recipe{} = recipe, board_id) do
    with {:ok, body} <- build_pin_body(recipe, board_id) do
      result =
        authed_request(user, fn token ->
          http_client().post(
            "#{api_base()}/pins",
            body,
            [
              {"Authorization", "Bearer #{token}"},
              {"Content-Type", "application/json"}
            ]
          )
        end)

      case result do
        {:error, :not_connected} ->
          Logger.warning(
            "[Pinterest] create_pin: no access token for user #{user.id} (recipe #{recipe.id})"
          )

          {:error, "No Pinterest account connected"}

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
    body =
      %{
        "name" => attrs["name"],
        "privacy" => attrs["privacy"] || "PUBLIC"
      }
      |> maybe_put_description(attrs["description"])
      |> Jason.encode!()

    result =
      authed_request(user, fn token ->
        http_client().post(
          "#{api_base()}/boards",
          body,
          [
            {"Authorization", "Bearer #{token}"},
            {"Content-Type", "application/json"}
          ]
        )
      end)

    case result do
      {:error, :not_connected} ->
        Logger.warning("[Pinterest] create_board: no access token for user #{user.id}")
        {:error, "No Pinterest account connected"}

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} when status in 200..299 ->
        Logger.info("[Pinterest] create_board: board created for user #{user.id}")

        case Jason.decode(resp_body) do
          {:ok, board} -> {:ok, board}
          _ -> {:ok, %{}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
        Logger.warning("[Pinterest] create_board: HTTP #{status} for user #{user.id} — #{resp_body}")
        {:error, "Pinterest API returned #{status}: #{resp_body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[Pinterest] create_board: request error for user #{user.id} — #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  @doc """
  Refreshes the user's access token using the stored refresh token. On success
  the new token (with any rotated refresh token) is persisted and `{:ok, user}`
  returned. On a 4xx the stored token is marked stale (so publishing
  short-circuits and the UI asks for a reconnect); transient errors leave the
  stored token untouched.
  """
  def refresh_user_token(%User{} = user) do
    token = user.pinterest_token || %{}

    case token["refresh_token"] do
      refresh_token when is_binary(refresh_token) and refresh_token != "" ->
        body =
          URI.encode_query(%{
            "grant_type" => "refresh_token",
            "refresh_token" => refresh_token
          })

        headers = [
          basic_auth_header(),
          {"Content-Type", "application/x-www-form-urlencoded"},
          {"Accept", "application/json"}
        ]

        case http_client().post("#{api_base()}/oauth/token", body, headers) do
          {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
          when status in 200..299 ->
            case Jason.decode(resp_body) do
              {:ok, %{"access_token" => _} = data} ->
                # Preserve the existing refresh token and scope unless Pinterest
                # rotated them in the response.
                new_token =
                  %{"refresh_token" => refresh_token, "scope" => token["scope"]}
                  |> Map.merge(data)
                  |> Token.build()

                Logger.info("[Pinterest] refresh_user_token: refreshed token for user #{user.id}")
                persist_token(user, new_token)

              _ ->
                {:error, :unexpected_response}
            end

          {:ok, %HTTPoison.Response{status_code: status, body: resp_body}}
          when status in 400..499 ->
            Logger.warning(
              "[Pinterest] refresh_user_token: HTTP #{status} for user #{user.id} — marking stale"
            )

            mark_stale(user, {:http_error, status, resp_body})
            {:error, {:http_error, status, resp_body}}

          {:ok, %HTTPoison.Response{status_code: status, body: resp_body}} ->
            {:error, {:http_error, status, resp_body}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error(
              "[Pinterest] refresh_user_token: request error for user #{user.id} — #{inspect(reason)}"
            )

            {:error, {:transport_error, reason}}
        end

      _ ->
        {:error, :no_refresh_token}
    end
  end

  @doc """
  Marks the stored token stale so publishing short-circuits and the UI shows a
  reconnect prompt.
  """
  def mark_stale(%User{} = user, reason) do
    token =
      (user.pinterest_token || %{})
      |> Map.put("status", "stale")
      |> Map.put("last_refresh_error", format_reason(reason))

    persist_token(user, token)
  end

  @doc """
  Users with a stored Pinterest access token — the refresh worker's candidate
  set. Corrupted error-map tokens lack the key and are excluded.
  """
  def list_users_with_pinterest_tokens do
    User
    |> where([u], fragment("? \\? ?", u.pinterest_token, "access_token"))
    |> Repo.all()
  end

  # Runs `request_fun.(token)` with the user's access token. On a 401 it
  # refreshes the token once and retries with the fresh one, returning the
  # original 401 result if the refresh itself fails. Returns the raw HTTP
  # result (or {:error, :not_connected}).
  defp authed_request(user, request_fun) do
    case access_token(user) do
      nil ->
        {:error, :not_connected}

      token ->
        case request_fun.(token) do
          {:ok, %HTTPoison.Response{status_code: 401}} = result ->
            Logger.info("[Pinterest] 401 for user #{user.id} — attempting token refresh")

            case refresh_user_token(user) do
              {:ok, refreshed_user} ->
                case access_token(refreshed_user) do
                  nil -> result
                  new_token -> request_fun.(new_token)
                end

              {:error, _reason} ->
                result
            end

          result ->
            result
        end
    end
  end

  defp persist_token(user, token) do
    Accounts.update_user_tokens(user, %{"pinterest_token" => token})
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp maybe_put_description(body, nil), do: body
  defp maybe_put_description(body, ""), do: body
  defp maybe_put_description(body, description), do: Map.put(body, "description", description)

  # Pinterest v5 pin limits: title ≤ 100 chars, description ≤ 800 chars.
  @title_max 100
  @description_max 800

  defp build_pin_body(%Recipe{} = recipe, board_id) do
    pin = %{
      board_id: board_id,
      title: String.slice(recipe.title || "", 0, @title_max),
      description: build_description(recipe),
      link: endpoint_module().url() <> "/browse/#{recipe.id}",
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

  # Build a rich pin description with the recipe's ingredients and steps (like the
  # Instagram/Facebook captions), followed by the hashtags. Pinterest caps the
  # description at 800 chars, so whole sections are dropped (instructions first,
  # then ingredients) before the body is hard-truncated — the header and hashtags
  # are always kept.
  defp build_description(%Recipe{} = recipe) do
    hashtags = hashtags_line(recipe)
    suffix = if hashtags == "", do: "", else: "\n\n" <> hashtags

    sections =
      [header(recipe), ingredients_section(recipe), instructions_section(recipe)]
      |> Enum.reject(&(&1 == ""))

    fit(sections, suffix)
  end

  defp header(%Recipe{} = recipe) do
    base = recipe.description || recipe.title || ""

    case recipe.cooking_time_lower_limit do
      nil -> base
      t -> String.trim("#{base} · #{t} min")
    end
  end

  defp ingredients_section(%Recipe{recipe_ingredients: items}) when is_list(items) do
    lines =
      items
      |> Enum.reject(&match?(%Ecto.Association.NotLoaded{}, &1.ingredient))
      |> Enum.map(fn ri ->
        [
          Mehungry.Social.Instagram.Caption.format_number(ri.quantity),
          Mehungry.Food.RecipeIngredient.unit_label(ri),
          ri.ingredient.name
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
      end)

    section("Ingredients", lines)
  end

  defp ingredients_section(_), do: ""

  defp instructions_section(%Recipe{steps: steps}) when is_list(steps) do
    lines =
      Enum.map(steps, fn step ->
        [Map.get(step, :title), Map.get(step, :description)]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n")
      end)
      |> Enum.reject(&(&1 == ""))

    section("Instructions", lines)
  end

  defp instructions_section(_), do: ""

  defp section(_title, []), do: ""
  defp section(title, lines), do: title <> "\n" <> Enum.join(lines, "\n")

  # Hashtags: the recipe's own hashtags (when loaded) plus the brand tag.
  defp hashtags_line(%Recipe{recipe_hashtags: hashtags}) when is_list(hashtags) do
    tags =
      hashtags
      |> Enum.map(fn rh ->
        case rh.hashtag do
          %{title: title} when is_binary(title) and title != "" -> "#" <> format_hashtag(title)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    (tags ++ ["#mehungry"]) |> Enum.uniq() |> Enum.join(" ")
  end

  defp hashtags_line(_), do: "#mehungry"

  defp format_hashtag(title) do
    title
    |> String.trim_leading("#")
    |> String.replace(~r/\s+/, "")
  end

  # Drop trailing sections (instructions, then ingredients) until the pin fits;
  # never drop the header before hard-truncating. The hashtag suffix is always kept.
  defp fit(sections, suffix) do
    body = Enum.join(sections, "\n\n")
    description = body <> suffix

    cond do
      String.length(description) <= @description_max ->
        description

      length(sections) > 1 ->
        fit(List.delete_at(sections, -1), suffix)

      true ->
        budget = max(@description_max - String.length(suffix) - 1, 0)
        String.slice(body, 0, budget) <> "…" <> suffix
    end
  end

  # Pinterest v5 token endpoint requires HTTP Basic auth
  # (base64(client_id:client_secret)). Credentials come from the same ueberauth
  # config the OAuth strategy uses.
  defp basic_auth_header do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Pinterest.OAuth, [])
    credentials = Base.encode64("#{config[:client_id]}:#{config[:client_secret]}")
    {"Authorization", "Basic #{credentials}"}
  end

  # Runtime seam: core cannot reference the web endpoint at compile time,
  # but pin links must point at the public site. The module is resolved at
  # runtime, mirroring the :social_media_publisher config-key pattern.
  defp endpoint_module do
    Application.get_env(:mehungry, :endpoint_module, MehungryWeb.Endpoint)
  end

  # :pinterest_api_base is set in runtime.exs from PINTEREST_ENV
  # (sandbox unless PINTEREST_ENV=live). Sandbox and live tokens are not
  # interchangeable — accounts must be reconnected after switching (the
  # ueberauth strategy reads the same key).
  defp api_base do
    Application.get_env(:mehungry, :pinterest_api_base, "https://api.pinterest.com/v5")
  end

  # HTTP seam so tests can stub the Pinterest API (must implement get/2, post/3
  # returning HTTPoison-shaped results).
  defp http_client do
    Application.get_env(:mehungry, :pinterest_http_client, HTTPoison)
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
