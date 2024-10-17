defmodule MehungryWeb.SvgComponents do
  @moduledoc """
  Provides Acess to svg that one way or another needds to be inline
  """
  @color_fill "#00A0D0"

  use MehungryWeb, :stateless_component

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

  def get_style(item_list, user_id) do
    has = Enum.any?(item_list, fn x -> x.user_id == user_id end)

    case has do
      true ->
        @color_fill

      false ->
        "#FFFFFF"
    end
  end

  def downvote_svg(assigns) do
    ~H"""
    <svg
      fill="#000000"
      phx-click="react"
      phx-value-type_="downvote"
      phx-value-id={@post.id}
      width="35px"
      height="35px"
      viewBox="0 0 24 24"
      id={"fd32d2d32#{@post.id}"}
      data-name="Flat Line"
      xmlns="http://www.w3.org/2000/svg"
      class="icon flat-line"
    >
      <path
        id={"sasd2342f#{@post.id}"}
        d="M11.38,20.79,3.77,14.87a1,1,0,0,1-.18-1.39L5.43,11a1,1,0,0,1,1.35-.23L9,12.26v-8a1,1,0,0,1,1-1h4a1,1,0,0,1,1,1v8l2.21-1.47a1,1,0,0,1,1.35.23l1.85,2.46a1,1,0,0,1-.19,1.39l-7.61,5.92A1,1,0,0,1,11.38,20.79Z"
        style="fill: transparent; stroke-width: 1.5;"
      >
      </path>
      <path
        id={"sasdf#{@post.id}"}
        d="M11.38,20.79,3.77,14.87a1,1,0,0,1-.18-1.39L5.43,11a1,1,0,0,1,1.35-.23L9,12.26v-8a1,1,0,0,1,1-1h4a1,1,0,0,1,1,1v8l2.21-1.47a1,1,0,0,1,1.35.23l1.85,2.46a1,1,0,0,1-.19,1.39l-7.61,5.92A1,1,0,0,1,11.38,20.79Z"
        style={"fill: " <> get_style(@post.downvotes, @user, fn x -> x.user_id end) <> "; stroke: #4b5563; stroke-linecap: round; stroke-linejoin: round; stroke-width: 1.5;"}
      >
      </path>
    </svg>
    """
  end

  def upvote_svg(assigns) do
    ~H"""
    <svg
      fill="#000000"
      phx-click="react"
      phx-value-type_="upvote"
      phx-value-id={@post.id}
      width="35px"
      height="35px"
      viewBox="0 0 24 24"
      id={"up-alt#{@post.id}"}
      data-name="Flat Line"
      xmlns="http://www.w3.org/2000/svg"
      class="icon flat-line"
    >
      <path
        id={"secondary#{@post.id}"}
        d="M20.41,10.79l-1.84,2.45a1,1,0,0,1-1.36.24L15,12v8a1,1,0,0,1-1,1H10a1,1,0,0,1-1-1V12L6.79,13.48a1,1,0,0,1-1.36-.24L3.59,10.79A1,1,0,0,1,3.78,9.4l7.61-5.92a1,1,0,0,1,1.22,0L20.22,9.4A1,1,0,0,1,20.41,10.79Z"
        style={"fill: " <> get_style(@post.upvotes, @user, fn x -> x.user_id end) <> "; stroke: #4b5563; stroke-linecap: round; stroke-linejoin: round; stroke-width: 1.5;"}
      >
      </path>
      <path
        id={"f43f2f4t#{@post.id}"}
        d="M20.41,10.79l-1.84,2.45a1,1,0,0,1-1.36.24L15,12v8a1,1,0,0,1-1,1H10a1,1,0,0,1-1-1V12L6.79,13.48a1,1,0,0,1-1.36-.24L3.59,10.79A1,1,0,0,1,3.78,9.4l7.61-5.92a1,1,0,0,1,1.22,0L20.22,9.4A1,1,0,0,1,20.41,10.79Z"
        style="fill: none; stroke: rgba(75, 85, 99, 0.7); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1.5;"
      >
      </path>
    </svg>
    """
  end
end
