defmodule MehungryWeb.HomeLive.Show do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  embed_templates("components/*")

  alias Mehungry.Accounts
  alias Mehungry.Posts.Comment
  alias Mehungry.Posts.Post
  alias Mehungry.Posts
  alias Mehungry.Users
  alias Mehungry.Food
  alias Mehungry.Food.RecipeUtils

  @color_fill "#00A0D0"

  def mount_search(%{"id" => id} = _params, session, socket) do
    user =
      case is_nil(session["user_token"]) do
        true ->
          nil

        false ->
          Accounts.get_user_by_session_token(session["user_token"])
      end

    post = Posts.get_post!(id)
    Posts.subscribe_to_post(%{post_id: id})

    {user_posts, user_follows} =
      case is_nil(user) do
        true ->
          {nil, nil}

        false ->
          user_posts = Users.list_user_saved_posts(user)
          user_posts = Enum.map(user_posts, fn x -> x.post_id end)
          user_follows = Users.list_user_follows(user)
          user_follows = Enum.map(user_follows, fn x -> x.follow_id end)
          {user_posts, user_follows}
      end

    {:ok,
     socket
     |> assign(
       :comment,
       case user do
         nil ->
           nil

         user ->
           %Comment{user_id: user.id, post_id: id}
       end
     )
     |> assign(:user, user)
     |> assign(:post, post)
     |> assign(:user_posts, user_posts)
     |> assign(:must_be_loged_in, nil)
     |> assign(:user_follows, user_follows)
     |> assign(:reply, nil)}
  end

  def get_style(item_list, user, get_attr) do
    has =
      case is_nil(user) or is_nil(item_list) or Enum.empty?(item_list) do
        true ->
          false

        false ->
          Enum.any?(item_list, fn x -> get_attr.(x) == user.id end)
      end

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end

  @impl true
  def handle_event(
        "save_user_recipe_dets",
        %{"recipe_id" => recipe_id, "dom_id" => dom_id},
        socket
      ) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {recipe_id, _ignore} = Integer.parse(recipe_id)
        recipe = Food.get_recipe!(recipe_id)
        toggle_user_saved_recipes(socket, recipe_id)
        user_recipes = Users.list_user_saved_recipes(socket.assigns.user)
        user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)
        # socket = stream_delete(socket, :recipes, recipe)
        # socket = stream_insert(socket, :recipes, recipe)
        socket = assign(socket, :user_recipes, user_recipes)

        {:noreply,
         push_patch(socket,
           to: ~p"/post/#{socket.assigns.post.id}/show_recipe/#{socket.assigns.recipe.id}"
         )}
    end
  end

  def toggle_user_saved_recipes(socket, recipe_id) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)

      false ->
        case Enum.any?(socket.assigns.user_recipes, fn x -> x == recipe_id end) do
          true ->
            Users.remove_user_saved_recipe(socket.assigns.user.id, recipe_id)

          false ->
            Users.save_user_recipe(socket.assigns.user.id, recipe_id)
        end
    end
  end

  def get_style2(item_list, user, positive) do
    IO.inspect(item_list, labe: "item_list")
    IO.inspect(user)
    IO.inspect(positive)

    has =
      case is_nil(user) or is_nil(item_list) or Enum.empty?(item_list) do
        true ->
          false

        false ->
          Enum.any?(item_list, fn x -> x.user_id == user.id and x.positive == positive end)
      end

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  def get_positive_votes(votes) do
    Enum.reduce(votes, 0, fn x, acc ->
      case x.positive do
        true ->
          acc + 1

        false ->
          acc
      end
    end)
  end

  @impl true
  def handle_event("vote_comment", %{"id" => comment_id, "reaction" => reaction}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        Mehungry.Posts.vote_comment(comment_id, socket.assigns.user.id, reaction)
        {:noreply, socket}
    end
  end

  def handle_event("add-reply-form", %{"id" => comment_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {comment_id, _} = Integer.parse(comment_id)

        socket =
          socket
          |> assign(:reply, %{comment_id: comment_id})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_post", %{"post_id" => post_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        {post_id, _ignore} = Integer.parse(post_id)
        toggle_user_saved_posts(socket, post_id)
        user_posts = Users.list_user_saved_posts(socket.assigns.user)
        user_posts = Enum.map(user_posts, fn x -> x.post_id end)
        socket = assign(socket, :user_posts, user_posts)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_user_follow", %{"follow_id" => follow_id}, socket) do
    {follow_id, _ignore} = Integer.parse(follow_id)
    toggle_user_follow(socket, follow_id)
    user_follows = Users.list_user_follows(socket.assigns.user)
    user_follows = Enum.map(user_follows, fn x -> x.follow_id end)
    socket = assign(socket, :user_follows, user_follows)
    {:noreply, socket}
  end

  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)

    {:noreply, socket}
  end

  def handle_event("react", %{"type_" => type, "id" => post_id}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        case type do
          "upvote" ->
            Posts.upvote_post(post_id, socket.assigns.user.id)

          "downvote" ->
            Posts.downvote_post(post_id, socket.assigns.user.id)
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{new_vote: _vote, type_: _type_}, socket) do
    post = socket.assigns.post
    post = Posts.get_post!(post.id)

    socket =
      socket
      |> assign(:post, post)

    {:noreply, socket}
  end

  def handle_info(%{new_comment: comment}, socket) do
    post = socket.assigns.post
    comment = Posts.get_comment!(comment.id)

    post = %Post{
      post
      | comments: Enum.into(Enum.filter(post.comments, fn x -> x.id != comment.id end), [comment])
    }

    socket =
      socket
      |> assign(:post, post)

    {:noreply, socket}
  end

  def handle_info({MehungryWeb.HomeLive.FormComponentComment, {:saved, _comment}}, socket) do
    post = socket.assigns.post

    socket =
      socket
      |> assign(:post, post)
      |> put_flash(:info, "Comment has been sent")

    {:noreply, socket}
  end

  def handle_info({MehungryWeb.HomeLive.FormComponentCommentAnswer, {:saved, _comment}}, socket) do
    post = socket.assigns.post

    socket =
      socket
      |> assign(:post, post)
      |> assign(:reply, nil)
      |> put_flash(:info, "Comment has been sent")

    {:noreply, socket}
  end

  defp get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> String.contains?(x.name, category_name) end)

    case length(category) > 0 do
      true ->
        {category_total, rest} =
          Enum.split_with(rest, fn x ->
            String.contains?(x.name, category_sum_name)
          end)

        case length(category_total) == 1 do
          true ->
            {Enum.into(Enum.at(category_total, 0), children: category), rest}

          false ->
            {%{
               amount: 111.1,
               measurement_unit: "to be defined",
               children: category,
               name: category_sum_name
             }, rest}
        end

      false ->
        {nil, rest}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, %{"id" => post_id}) do
    socket
    |> assign(:page_title, page_title(socket.assigns.live_action))
  end

  defp apply_action(socket, :show_recipe, %{"id" => id, "rec_id" => rec_id}) do
    recipe = Food.get_recipe!(id)
    IO.inspect(recipe)

    recipe_nutrients =
      RecipeUtils.calculate_recipe_nutrition_value(recipe)

    rest =
      Enum.filter(recipe_nutrients.flat_recipe_nutrients, fn x ->
        Float.round(x.amount, 3) != 0
      end)

    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Fatty acids, total monounsaturated")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Fatty acids, total polyunsaturated")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Fatty acids, total saturated")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Fatty acids, total trans")
    {vitamins, rest} = Enum.split_with(rest, fn x -> String.contains?(x.name, "Vitamin") end)

    vitamins_all =
      case length(vitamins) > 0 do
        true ->
          %{name: "Vitamins", amount: nil, measurement_unit: nil, children: vitamins}

        false ->
          nil
      end

    nuts_pre = [mufa_all, pufa_all, sfa_all, tfa_all, vitamins_all]
    nuts_pre = Enum.filter(nuts_pre, fn x -> !is_nil(x) end)

    nuts_pre =
      Enum.map(nuts_pre, fn x ->
        case is_map(x) do
          true ->
            x

          false ->
            Enum.into(x, %{})
        end
      end)

    nutrients = nuts_pre ++ rest
    nutrients = Enum.filter(nutrients, fn x -> !is_nil(x) end)
    energy = Enum.find(nutrients, fn x -> String.contains?(x.name, "Energy") end)

    energy =
      case energy.measurement_unit do
        "kilojoule" ->
          %{energy | amount: energy.amount * 0.2390057361, measurement_unit: "kcal"}

        _ ->
          energy
      end

    carb = Enum.find(nutrients, fn x -> String.contains?(x.name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn x -> String.contains?(x.name, "Protein") end)
    fiber = Enum.find(nutrients, fn x -> String.contains?(x.name, "Fiber") end)
    fat = Enum.find(nutrients, fn x -> String.contains?(x.name, "Total lipid") end)

    primaries = [energy, fat, carb, protein, fiber]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    nutrients = primaries ++ nutrients

    user = socket.assigns.user
    query_str = ""

    user_profile =
      case is_nil(user) do
        true ->
          nil

        false ->
          Accounts.get_user_profile_by_user_id(user.id)
      end

    user_recipes =
      case is_nil(user) do
        true ->
          []

        false ->
          user_recipes = Users.list_user_saved_recipes(user)
          user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)
      end

    socket
    |> assign(:nutrients, nutrients)
    |> assign(:primary_size, length(primaries))
    |> assign(:recipe, recipe)
    |> assign(:user_recipes, user_recipes)
    |> assign(:page_title, page_title(socket.assigns.live_action))
  end

  def toggle_user_saved_posts(socket, post_id) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        case Enum.any?(socket.assigns.user_posts, fn x -> x == post_id end) do
          true ->
            Users.remove_user_saved_post(socket.assigns.user.id, post_id)

          false ->
            Users.save_user_post(socket.assigns.user.id, post_id)
        end
    end
  end

  def toggle_user_follow(socket, follow_id) do
    case Enum.any?(socket.assigns.user_follows, fn x -> x == follow_id end) do
      true ->
        Users.remove_user_follow(socket.assigns.user.id, follow_id)

      false ->
        Users.save_user_follow(socket.assigns.user.id, follow_id)
    end
  end

  defp page_title(:show_recipe), do: "Show Recipe"
  defp page_title(:show), do: "Show Post"
  defp page_title(:edit), do: "Edit User profile"
end
