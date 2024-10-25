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

  def created_recipes_svg(assigns) do
    ~H"""
    <svg
      style="display: inline; fill: #ffffff"
      width="20px"
      height="20px"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M19 19.2674V7.84496C19 5.64147 17.4253 3.74489 15.2391 3.31522C13.1006 2.89493 10.8994 2.89493 8.76089 3.31522C6.57467 3.74489 5 5.64147 5 7.84496V19.2674C5 20.6038 6.46752 21.4355 7.63416 20.7604L10.8211 18.9159C11.5492 18.4945 12.4508 18.4945 13.1789 18.9159L16.3658 20.7604C17.5325 21.4355 19 20.6038 19 19.2674Z"
        stroke-width="2"
        stroke-linecap="round"
        fill="#fffff"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  def saved_recipes_svg(assigns) do
    ~H"""
    <svg
      height="20px"
      width="20px"
      style="display: inline;"
      version="1.1"
      id="_x32_"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      viewBox="0 0 512 512"
      xml:space="preserve"
    >
      <g>
        <path
          class="st0"
          d="M512,200.388c-0.016-63.431-51.406-114.828-114.845-114.836c-11.782-0.008-23.118,1.952-33.846,5.275
    		C338.408,58.998,299.57,38.497,256,38.497c-43.57,0-82.408,20.501-107.309,52.329c-10.737-3.322-22.073-5.283-33.846-5.275
    		C51.406,85.56,0.016,136.957,0,200.388c0.008,54.121,37.46,99.352,87.837,111.523c-11.368,35.548-21.594,81.104-21.538,140.848
    		v20.744h379.402v-20.744c0.056-59.744-10.169-105.3-21.538-140.848C474.54,299.741,511.984,254.509,512,200.388z M449.023,252.265
    		c-13.322,13.297-31.505,21.456-51.803,21.48l-0.51-0.007l-30.524-0.77l10.534,28.66c11.977,32.704,24.464,72.928,27,130.387
    		H108.281c2.536-57.459,15.023-97.683,27-130.387l10.534-28.669l-31.043,0.786c-20.29-0.024-38.473-8.184-51.803-21.48
    		c-13.305-13.338-21.473-31.546-21.481-51.876c0.008-20.322,8.176-38.53,21.481-51.867c13.346-13.306,31.554-21.473,51.876-21.482
    		c11.725,0.008,22.689,2.731,32.493,7.577l17.251,8.54l9.804-16.571C190.956,98.663,221.222,79.977,256,79.985
    		c34.778-0.008,65.044,18.678,81.606,46.601l9.796,16.571l17.26-8.54c9.804-4.846,20.761-7.568,32.493-7.577
    		c20.322,0.008,38.531,8.176,51.876,21.482c13.305,13.338,21.473,31.545,21.481,51.867
    		C470.505,220.719,462.337,238.927,449.023,252.265z"
        />
      </g>
    </svg>
    """
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
      class="icon flat-line z-40"
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
