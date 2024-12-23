defmodule MehungryWeb.RecipeBrowserFeatureTest do
  use MehungryWeb.FeatureCase, async: false

  import Mehungry.FoodFixtures

  alias Mehungry.Accounts

  describe "Recipe Browser Index" do
    setup(%{session: session}) do
      {session, user} = log_in(%{session: session})
      user_profile = Accounts.get_user_profile_by_user_id(user.id)

      Accounts.update_user_profile(
        user_profile,
        %{onboarding_level: 1}
      )

      _recipe_3 = recipe_fixture(user, %{title: "Recipe 1"})
      _recipe_2 = recipe_fixture(user, %{title: "Recipe 6"})
      _recipe_4 = recipe_fixture(user, %{title: "Recipe 15", description: "Puta madre"})

      _recipe_5 =
        recipe_fixture(user, %{title: "Recipe 12341", description: "adsfafdfdasdf asd "})

      recipe =
        recipe_fixture(user, %{
          title: "Recipe 2",
          description: "SOme more ellaborate decission #thetag"
        })

      {:ok, session: session, recipe: recipe, user: user}
    end

    test "Test Listing Hashtag Recipes Viewing one and go back to listing", %{
      session: session,
      recipe: recipe,
      user: _user
    } do
      link_id = "recipe-card-details-link-" <> Integer.to_string(recipe.id)
      query = Query.link(link_id)

      element =
        session
        |> visit("/search/hashtag/thetag")
        |> find(query)
        |> Element.click()

      sleep(session)

      assert current_path(session) == "/browse/" <> Integer.to_string(recipe.id)

      Element.send_keys(element, [:escape])
      sleep(session)

      assert current_path(session) == "/search/hashtag/thetag"

      whatever = all(session, Query.css(".recipe_title"))
      assert length(whatever) == 1
    end

    test "Test Listing Recipes Viewing one and go back to listing", %{
      session: session,
      recipe: recipe,
      user: _user
    } do
      link_id = "recipe-card-details-link-" <> Integer.to_string(recipe.id)
      query = Query.link(link_id)

      element =
        session
        |> visit("/browse")
        |> find(query)
        |> Element.click()

      sleep(session)

      assert current_path(session) == "/browse/" <> Integer.to_string(recipe.id)

      Element.send_keys(element, [:escape])
      sleep(session)

      assert current_path(session) == "/browse"

      whatever = all(session, Query.css(".recipe_title"))
      assert length(whatever) == 5
    end
  end

  def sleep(session) do
    Process.sleep(200)
    session
  end

  @user_remember_me "_mehungry_web_user_remember_me"

  def log_in(%{session: session} = _context) do
    user = Mehungry.AccountsFixtures.user_fixture()
    user_token = Mehungry.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:mehungry_web, MehungryWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(@user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(@user_remember_me, conn.resp_cookies[@user_remember_me][:value])

    {session, user}
  end
end
