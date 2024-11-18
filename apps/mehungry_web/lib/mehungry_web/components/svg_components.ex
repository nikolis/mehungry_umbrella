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

  def get_default_recipe_image(assigns) do
    ~H"""
    <svg
      version="1.1"
      id="Layer_1"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      viewBox="0 0 512 512"
      class="col-span-2 max-h-40"
      xml:space="preserve"
    >
      <polygon
        style="fill:#19CCFE;"
        points="282.819,132.794 256,132.794 229.181,132.794 0,89.95 0,434.07 229.181,476.914
    282.819,476.914 512,434.07 512,89.95 "
      />
      <path
        style="fill:#F7EE00;"
        d="M512,89.95l-32.339-54.864L303.695,77.702C270.013,85.389,256,102.887,256,132.794h26.819L512,89.95z
    "
      />
      <path
        style="fill:#FFFC99;"
        d="M256,132.794c0-29.907-14.013-47.405-47.695-55.092L32.339,35.086L0,89.95l229.181,42.844H256z"
      />
      <polygon style="fill:#9BE7FE;" points="0,89.95 0,434.07 229.181,476.914 229.181,132.794 " />
      <path
        style="fill:#0BAEBC;"
        d="M142.193,165.278l-0.001,47.445c0,8.67-2.482,15.733-7.175,20.427
    c-1.379,1.379-2.985,2.543-4.754,3.533v-71.404H98.915v71.402c-1.768-0.99-3.373-2.154-4.751-3.531
    c-4.695-4.695-7.176-11.758-7.175-20.427V165.28H55.642v47.441c-0.001,17.163,5.655,31.891,16.358,42.594
    c7.276,7.276,16.417,12.213,26.917,14.631v142.421h31.347v-142.42c10.5-2.418,19.643-7.355,26.92-14.632
    c10.702-10.7,16.358-25.429,16.358-42.593l0.001-47.445L142.193,165.278L142.193,165.278z"
      />
      <path
        style="fill:#088690;"
        d="M397.41,160.914c-21.882,0-39.616,17.735-39.615,39.614l-0.001,43.29
    c0,16.309,9.86,30.312,23.943,36.386v132.162h31.347V280.204c14.082-6.074,23.942-20.077,23.941-36.385l0.002-43.29
    C437.022,178.65,419.287,160.915,397.41,160.914z"
      />
      <rect x="229.177" y="132.796" style="fill:#71DFFE;" width="53.635" height="344.116" />
    </svg>
    """
  end

  def get_loading(assigns) do
    ~H"""
    <div style="max-width: 60vh; margin: auto;">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
        <radialGradient
          id="a12"
          cx=".66"
          fx=".66"
          cy=".3125"
          fy=".3125"
          gradientTransform="scale(1.5)"
        >
          <stop offset="0" stop-color="#00A0D0"></stop>
          <stop offset=".3" stop-color="#00A0D0" stop-opacity=".9"></stop>
          <stop offset=".6" stop-color="#00A0D0" stop-opacity=".6"></stop>
          <stop offset=".8" stop-color="#00A0D0" stop-opacity=".3"></stop>
          <stop offset="1" stop-color="#00A0D0" stop-opacity="0"></stop>
        </radialGradient>
        <circle
          transform-origin="center"
          fill="none"
          stroke="url(#a12)"
          stroke-width="15"
          stroke-linecap="round"
          stroke-dasharray="200 1000"
          stroke-dashoffset="0"
          cx="100"
          cy="100"
          r="70"
        >
          <animateTransform
            type="rotate"
            attributeName="transform"
            calcMode="spline"
            dur="2"
            values="360;0"
            keyTimes="0;1"
            keySplines="0 0 1 1"
            repeatCount="indefinite"
          >
          </animateTransform>
        </circle>
        <circle
          transform-origin="center"
          fill="none"
          opacity=".2"
          stroke="#FF156D"
          stroke-width="15"
          stroke-linecap="round"
          cx="100"
          cy="100"
          r="70"
        >
        </circle>
      </svg>
    </div>
    """
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
