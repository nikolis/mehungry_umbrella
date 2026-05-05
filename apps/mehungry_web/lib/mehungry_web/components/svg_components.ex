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

  def get_edit_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="size-6"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"
      />
    </svg>
    """
  end

  def get_empty(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="200" height="200">
      <!-- Empty State: Magnifying Glass + Fork -->
      <circle cx="85" cy="85" r="50" fill="none" stroke="#334155" stroke-width="4" />
      <line
        x1="120"
        y1="120"
        x2="150"
        y2="150"
        stroke="#334155"
        stroke-width="4"
        stroke-linecap="round"
      />
      
    <!-- Plate -->
      <ellipse cx="120" cy="140" rx="45" ry="12" fill="#1E293B" stroke="#334155" stroke-width="2" />
      <ellipse cx="120" cy="138" rx="35" ry="8" fill="#0F172A" />
      
    <!-- Fork -->
      <line x1="100" y1="110" x2="100" y2="145" stroke="#475569" stroke-width="2" />
      <line x1="92" y1="110" x2="92" y2="105" stroke="#475569" stroke-width="2" />
      <line x1="96" y1="108" x2="96" y2="103" stroke="#475569" stroke-width="2" />
      <line x1="100" y1="107" x2="100" y2="102" stroke="#475569" stroke-width="2" />
      <line x1="104" y1="108" x2="104" y2="103" stroke="#475569" stroke-width="2" />
      <line x1="108" y1="110" x2="108" y2="105" stroke="#475569" stroke-width="2" />
      
    <!-- Question Mark -->
      <text
        x="135"
        y="80"
        font-family="system-ui"
        font-size="28"
        font-weight="bold"
        fill="#F97316"
        text-anchor="middle"
      >
        ?
      </text>
    </svg>
    """
  end

  @doc """
  Compact logo for collapsed header state
  """
  def logo_compact(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 50" width="120" height="30" class="">
      <!-- Simplified cubes for compact view -->
      <polygon points="25,35 35,28 45,35 45,45 35,52 25,45" fill="#14B8A6" opacity="0.9" />
      <polygon points="35,20 45,13 55,20 55,30 45,37 35,30" fill="#5EEAD4" opacity="0.9" />
      <polygon points="45,13 55,6 65,13 65,23 55,30 45,23" fill="#99F6E4" opacity="0.9" />
      
    <!-- Compact text -->
      <text
        x="75"
        y="30"
        font-family="'Inter', sans-serif"
        font-size="20"
        font-weight="800"
        fill="#F8FAFC"
        letter-spacing="1"
      >
        M3<tspan fill="#F97316">HUNGRY</tspan>
      </text>
    </svg>
    """
  end

  def get_logo(assigns) do
      ~H"""
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 450 120">
  <defs>
    <!-- Warm Orange gradients matching favicon -->
    <linearGradient id="topCubeOrange" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBBF24" />
      <stop offset="50%" stop-color="#F97316" />
      <stop offset="100%" stop-color="#EA580C" />
    </linearGradient>
    <linearGradient id="middleCubeOrange" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#F97316" />
      <stop offset="50%" stop-color="#EA580C" />
      <stop offset="100%" stop-color="#C2410C" />
    </linearGradient>
    <linearGradient id="bottomCubeOrange" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#EA580C" />
      <stop offset="100%" stop-color="#7C2D12" />
    </linearGradient>
  </defs>

  <!-- Bottom Cube -->
  <polygon points="60,95 80,82 100,95 100,115 80,128 60,115" fill="url(#bottomCubeOrange)" />
  <polygon points="80,82 100,95 80,108 60,95" fill="#7C2D12" opacity="0.7" />

  <!-- Middle Cube -->
  <polygon points="80,65 100,52 120,65 120,85 100,98 80,85" fill="url(#middleCubeOrange)" />
  <polygon points="100,52 120,65 100,78 80,65" fill="#C2410C" opacity="0.7" />

  <!-- Top Cube -->
  <polygon points="100,38 120,25 140,38 140,58 120,71 100,58" fill="url(#topCubeOrange)" />
  <polygon points="120,25 140,38 120,51 100,38" fill="#F97316" opacity="0.8" />

  <!-- Lines -->
  <line x1="100" y1="58" x2="100" y2="78" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />
  <line x1="80" y1="65" x2="80" y2="82" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />
  <line x1="120" y1="52" x2="120" y2="65" stroke="#FBBF24" stroke-width="2" stroke-dasharray="3,3" />

  <!-- Text - Dark slate to match favicon text -->
  <text x="160" y="65" font-family="'Inter', system-ui, -apple-system, sans-serif" font-size="38" font-weight="800" fill="#0F172A" letter-spacing="2">
    M3<tspan fill="#EA580C">HUNGRY</tspan>
  </text>

  <!-- Tagline -->
  <text x="160" y="88" font-family="'Inter', system-ui, -apple-system, sans-serif" font-size="11" fill="#64748B" letter-spacing="3">
    ANALYZE • SHARE • CONNECT
  </text>
</svg>
    """
  end

  def get_default_recipe_image(assigns) do
    ~H"""
    <svg
      version="1.1"
      id="Layer_1"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      viewBox="0 0 512 512"
      class="col-span-2 max-h-60"
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
