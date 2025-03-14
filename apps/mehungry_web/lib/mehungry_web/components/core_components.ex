defmodule MehungryWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use MehungryWeb, :stateless_component
  alias Phoenix.LiveView.JS
  alias Mehungry.Food
  alias Mehungry.Accounts
  import MehungryWeb.Gettext

  def drop_down(assigns) do
    ~H"""
    <div style="margin-bottom: 0.75rem;" class="mx-8 sm:mx-0">
      <div class="flex gap-2">
        <.link
          patch={"/profile/"<>Integer.to_string(@user.id)}
          style="min-height: 50px; min-width: 50px;"
        >
          <%= if @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 50px; height: 50px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="h-12 w-12" />
          <% end %>
        </.link>
        <div class="flex flex-col justify-center w-full">
          <div class="text-sm font-bold leading-4">
            <.link patch={"/profile/"<>Integer.to_string(@user.id)}>
              <%= @user.email %>
            </.link>
            <div class="cursor-pointer" phx-click="save_user_follow" phx-value-follow_id={@user.id}>
            </div>
          </div>
          <div class="text-sm leading-4">
            <%= "#{count_user_created_recipes(@user.id)} posted recipes" %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def count_user_created_recipes(user_id) do
    Food.count_user_created_recipes(user_id)
  end

  def count_user_followers(user_id) do
    Accounts.count_user_followers(user_id)
  end

  def count_user_following(user_id) do
    Accounts.count_user_following(user_id)
  end

  @doc """
  """
  def share_button(assigns) do
    ~H"""
    <div
      class="relative"
      id={"share_utils_toggle" <> Integer.to_string(@post.id) }
      phx-click-away={
        Phoenix.LiveView.JS.remove_class("drop_down_visible ",
          to: "#share_items_list" <> Integer.to_string(@post.id)
        )
      }
      phx-click={
        Phoenix.LiveView.JS.toggle_class("drop_down_visible ",
          to: "#share_items_list" <> Integer.to_string(@post.id)
        )
      }
    >
      <.icon name="hero-share" class="stroke-white h-7 w-7 " />
      <div
        phx-hook="Copy"
        class="drop_down_home  inner_utils m-auto pr-4"
        data-to={"#control-codes" <> Integer.to_string(@post.id)}
        id={"share_items_list"<> Integer.to_string(@post.id)}
      >
        <input
          type="text"
          class="hidden"
          id={"control-codes"<> Integer.to_string(@post.id)}
          value={~p"/show_recipe/#{Integer.to_string(@post.reference_id)}"}
        />
        <.icon
          name="hero-link"
          style="width: 40px;"
          class="m-auto h-7 w-9 bg-white  text-white cursor-pointer"
        />

        <img
          src="/images/instagram-svgrepo-com.svg"
          width="full"
          class="m-auto h-7 w-10   text-white cursor-pointer bg-transparent overflow-hidden"
        />

        <.link
          id={"link-to-recipe-#{@post.reference_id}"}
          class="block w-full overflow-hidden"
          style="width: 50px;"
          patch={~p"/share_social_media/#{@post.reference_id}"}
        >
          <img
            src="/images/facebook-svgrepo-com (1).svg"
            width="full"
            class="m-auto h-7 w-10  text-white cursor-pointer bg-transparent inline w-full"
          />
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  Renders a user details presentation for the moment just in profile maybe needs to be moved in more speicic context. 
  """
  def user_details_card(
        %{
          user_follows: _user_follows,
          user: %Mehungry.Accounts.User{} = _user
        } = assigns
      ) do
    ~H"""
    <div style="margin-bottom: 0.75rem; " class="w-full">
      <div class=" flex justify-center gap-2 xl:gap-28 w-11/12 m-auto sm:w-full m-0 flex-wrap ">
        <.link
          patch={"/profile/"<>Integer.to_string(@user.id)}
          style="min-height: 100px; min-width: 100px;"
        >
          <%= if @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 130px; height: 130px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="w-full h-full" />
          <% end %>
        </.link>
        <div class="flex flex-col justify-center w-fit h-full">
          <div class="text-sm  font-bold leading-4">
            <.link patch={"/profile/"<>Integer.to_string(@user.id)} class="flex flex-wrap">
              <span class="w-full text-center sm:w-fit text-lg md:text-2xl mr-4">
                <%= @user.email %>
              </span>
            </.link>

            <%= if @current_user != @user do %>
              <div class="w-full md:w-fit">
                <%= if @user.id not in @user_follows do %>
                  <div class="m-auto h-full w-fit sm:m-0  mt-4">
                    <button
                      class="primary_button  p-2 m-auto text-md px-2 font-bold"
                      type="button"
                      id={"toggle_user_follow#{@user.id}"}
                      phx-click="save_user_follow"
                      phx-value-follow_id={@user.id}
                    >
                      Follow!
                    </button>
                  </div>
                <% else %>
                  <div class="mt-auto mb-auto self-end w-full">
                    <button
                      class="primary_button_complementary  m-auto"
                      phx-click="save_user_follow"
                      phx-value-follow_id={@user.id}
                    >
                      <span class="text-md px-2 font-bold"> Following </span>
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
            <div class="cursor-pointer" phx-click="save_user_follow" phx-value-follow_id={@user.id}>
            </div>
          </div>
          <div class="flex gap-2 mt-2 flex-wrap justify-center sm:justify-start	">
            <div class="text-sm leading-4 ">
              <span class="font-semibold text-lg">
                <%= "#{count_user_created_recipes(@user.id)}" %>
              </span>
              <span class="text-lg"> Posted recipes </span>
            </div>
            <div class="text-sm leading-4 ">
              <span class="font-semibold text-lg"><%= "#{count_user_followers(@user.id)}" %></span>
              <span class="text-lg"> Followers </span>
            </div>

            <div class="text-sm leading-4">
              <span class="font-semibold text-lg"><%= "#{count_user_following(@user.id)}" %></span>
              <span class="text-lg"> Following </span>
            </div>
          </div>
          <div class="mt-2 w-fit m-auto sm:m-0">
            <div class="font-semibold text-center sm:text-left"><%= @user_profile.alias %></div>
            <div class="text-center sm:text-left"><%= @user_profile.intro %></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def user_overview_card(%{user: %Mehungry.Accounts.User{}, user_follows: nil} = assigns) do
    ~H"""
    <div class="mx-8 sm:mx-0">
      <div class="flex gap-2">
        <.link
          patch={"/profile/"<>Integer.to_string(@user.id)}
          style="min-height: 50px; min-width: 50px;"
        >
          <%= if @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 50px; height: 50px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="h-12 w-12" />
          <% end %>
        </.link>
        <div class="flex flex-col justify-center w-full">
          <div class="text-sm font-bold leading-4">
            <.link patch={"/profile/"<>Integer.to_string(@user.id)}>
              <%= @user.email %>
            </.link>
            <div class="cursor-pointer" phx-click="save_user_follow" phx-value-follow_id={@user.id}>
            </div>
          </div>
          <div class="text-sm leading-4">
            <%= "#{count_user_created_recipes(@user.id)} posted recipes" %>
          </div>
          <div class="text-sm leading-4">
            <%= "#{count_user_created_recipes(@user.id)} posted recipesfasdafsdafsafsd" %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def get_post_age(%Mehungry.Posts.Post{} = post) do
    diff = NaiveDateTime.diff(NaiveDateTime.local_now(), post.updated_at, :second)
    IO.inspect(diff)
    "23m"
    get_diff(diff)
  end

  5500

  defp get_diff(diff) do
    if diff < 60 do
      Integer.to_string(round(diff)) <> "s"
    else
      get_diff(diff / 60, "min")
    end
  end

  defp get_diff(diff, "min") do
    if diff < 60 do
      Integer.to_string(round(diff)) <> "m"
    else
      get_diff(diff / 60, "hour")
    end
  end

  defp get_diff(diff, "hour") do
    if diff < 24 do
      Integer.to_string(round(diff)) <> "h"
    else
      get_diff(diff / 24, "day")
    end
  end

  defp get_diff(diff, "day") do
    if diff < 7 do
      Integer.to_string(round(diff)) <> "d"
    else
      get_diff(diff / 7, "week")
    end
  end

  defp get_diff(diff, "week") do
    if diff < 4 do
      Integer.to_string(round(diff)) <> "w"
    else
      get_diff(diff / 4, "month")
    end
  end

  defp get_diff(diff, "month") do
    Integer.to_string(round(diff)) <> "m"
  end

  @doc """
  Renders a user overview card to be used to present the user on their activities such as a recipe post or a comment. 
  """
  def user_overview_card(
        %{
          user_follows: _user_follows,
          user: %Mehungry.Accounts.User{} = _user
        } = assigns
      ) do
    post = Map.get(assigns, :post, nil)
    assigns = Map.put(assigns, :post, post)

    ~H"""
    <div style="margin-bottom: 0.75rem; " class="w-full ">
      <div class=" flex gap-2 w-11/12 m-auto sm:w-full m-0 ">
        <.link
          patch={"/profile/"<>Integer.to_string(@user.id)}
          style="min-height: 50px; min-width: 50px;"
        >
          <%= if @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 50px; height: 50px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="h-12 w-12" />
          <% end %>
        </.link>
        <div class="flex flex-col justify-center w-full">
          <div class="text-sm font-bold leading-4">
            <.link patch={"/profile/"<>Integer.to_string(@user.id)}>
              <%= @user.email %>
              <%= if not is_nil(@post) do %>
                <span class="font-normal text-greyfriend3"><%= get_post_age(@post) %></span>
              <% end %>
            </.link>
            <div class="cursor-pointer" phx-click="save_user_follow" phx-value-follow_id={@user.id}>
            </div>
          </div>
          <div class="text-sm leading-4">
            <%= "#{count_user_created_recipes(@user.id)} posted recipes" %>
          </div>
        </div>
        <%= if @user.id in @user_follows do %>
          <button
            class="text-primary font-semibold  text-sm sm:text-xl "
            phx-click="save_user_follow"
            phx-value-follow_id={@user.id}
          >
            Following
          </button>
        <% else %>
          <button
            class="text-complementary font-semibold  text-sm sm:text-xl "
            phx-click="save_user_follow"
            phx-value-follow_id={@user.id}
          >
            Follow
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Recipe Hedder
  """
  def recipe_header_card(
        %{
          user_follows: _user_follows,
          user: %Mehungry.Accounts.User{} = _user
        } = assigns
      ) do
    ~H"""
    <div class="footer_user_overview w-fit absolute top-10 right-0 left-0 m-auto rounded-full z-10">
      <div class=" flex gap-2 w-fit m-auto sm:w-full m-0 ">
        <div class="flex flex-col justify-center w-full">
          <div class="text-sm font-semibold leading-4 text-white">
            <div class="text-center text-2xl px-6 max-h-16 overflow-hidden">
              <%= @post.reference.title %>
            </div>
            <div class="text-center text-base px-6 pb-2"><%= @post.reference.description %></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a user overview card to be used to present the user on their activities such as a recipe post or a comment. 
  """
  def footer_user_overview_card(
        %{
          user_follows: _user_follows,
          user: %Mehungry.Accounts.User{} = _user
        } = assigns
      ) do
    ~H"""
    <div class="footer_user_overview w-full absolute bottom-10 right-0 left-0 m-auto rounded-full z-10">
      <div class=" flex gap-2 w-11/12 m-auto sm:w-full m-0 ">
        <.link
          patch={"/profile/"<>Integer.to_string(@user.id)}
          style="min-height: 50px; min-width: 50px;"
        >
          <%= if @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 50px; height: 50px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="h-12 w-12" />
          <% end %>
        </.link>
        <div class="flex flex-col justify-center w-full">
          <div class="text-base font-bold text-white leading-4">
            <.link patch={"/profile/"<>Integer.to_string(@user.id)}>
              <%= @user.email %>
            </.link>
            <div class="cursor-pointer" phx-click="save_user_follow" phx-value-follow_id={@user.id}>
            </div>
          </div>
          <div class="text-sm font-semibold leading-4 text-white">
            <%= "#{count_user_created_recipes(@user.id)} posted recipes" %>
          </div>
        </div>
        <.follow_button user_follows={@user_follows} user={@user} />
      </div>
    </div>
    """
  end

  def follow_button(%{user_follows: nil} = assigns) do
    ~H"""
    <div class="self-end m-auto">
      <a
        href={~p"/users/log_in"}
        class="primary_button px-2 py-1  sm:px-4 sm:py-3 m-auto sm:font-semibold h-full w-full"
        phx-click="save_user_follow"
        phx-value-follow_id={@user.id}
      >
        Follow
      </a>
    </div>
    """
  end

  def follow_button(assigns) do
    ~H"""
    <%= if @user.id in @user_follows do %>
      <div class="my-auto self-end w-fit relative mx-2">
        <button
          class="primary_button_complementary px-2 py-1  sm:px-4 sm:py-3 m-auto sm:font-bold h-full w-full"
          phx-click="save_user_follow"
          phx-value-follow_id={@user.id}
        >
          Following
        </button>
      </div>
    <% else %>
      <div class="self-end m-auto">
        <button
          class="primary_button px-2 py-1  sm:px-4 sm:py-3 m-auto sm:font-semibold h-full w-full"
          phx-click="save_user_follow"
          phx-value-follow_id={@user.id}
        >
          Follow
        </button>
      </div>
    <% end %>
    """
  end

  def dialog_button(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-2  lg:p-14 shadow-lg ring-1 transition"
            >
              <div id={"#{@id}-content"}>
                <%= render_slot(@inner_block) %>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-2 min-h-96 lg:p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <%= render_slot(@inner_block) %>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        <%= @title %>
      </p>
      <p class="mt-2 text-sm leading-5"><%= msg %></p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title="Success!" flash={@flash} />
      <.flash kind={:error} title="Error!" flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        Hang in there while we get back on track
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <%= render_slot(@inner_block, f) %>
      <div :for={action <- @actions} class="mt-6 flex items-center justify-between gap-6">
        <%= render_slot(action, f) %>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value myself)
  slot :inner_block, required: true

  def button(%{type: "primary"} = assigns) do
    ~H"""
    <button
      type={@type}
      style="margin-inline: auto; position: absolute; bottom: 1.2rem; right: 1.2rem;"
      class={[
        "primary_button",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "absolute right-5 button_outline_primary modal-submit-button",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(readonly checkbox color date datetime-local email file hidden month number password select_component
               range radio search select tel text textarea time url week full-text comment checkbox_covered)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []

  attr :index, :integer,
    required: false,
    doc: "The index in case the input exists within form_for kind of setup"

  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step myself)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # All type readonly are handled here...
  def input(%{type: "readonly"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form w-full h-full">
      <input
        type="text"
        name={@name}
        id={@id}
        readonly
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              " w-full sm:w-fit text-2xl text-center w-fit m-auto uppercase	font-medium	mb-4 rounded-lg border-greyfriend2 border-2 border-transparent ring-complementaryl ring-2	h-full",
              @errors == [] && "",
              @errors != [] && " ring-rose-400  focus:ring-rose-400"
            ]
        }
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-md font-medium leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-complementaryl text-complementary focus:ring-0 font-medium"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "checkbox_covered"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name} style="height: 100%; margin: auto" class="">
      <label
        id={"button_remove_ingredient"<> Integer.to_string(@index)}
        class="w-full relative "
        style="background-image: url('/images/remove.svg'); height: 10px; background-position: center; background-repeat: no-repeat; background-size: 25px 40%; height: 60px; display: block; margin: auto;"
      >
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-complementaryl text-complementary focus:ring-0 font-medium w-full h-full  invisible "
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      style="display: none;"
      id={@id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
    />
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form">
      <textarea
        id={@id}
        name={@name}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "h-full rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym focus:ring-2 mt-2"
            ]
        }
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.label for={@id}><%= @label %></.label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "full-text"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form">
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "input_full",
              "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
              @errors == [] && "border-zinc-300 focus:border-zinc-400",
              @errors != [] && "border-rose-400 focus:border-rose-400"
            ]
        }
        {@rest}
      />
      <.label for={@id} class="placeholder"><%= @label %></.label>

      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "flatpicker"} = assigns) do
    ~H"""
    <div
      phx-feedback-for={@name}
      class="input-form flatpickr"
      phx-hook="DatePicker"
      id={(@id || @name) <> "as"}
      style=""
    >
      <input
        type="hidden"
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "input_full",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />

      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # Input type for select component
  def input(%{type: "select_component"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class=" input-form  relative h-full">
      <svg
        phx-click="toggle-listing"
        phx-target={assigns.rest.myself}
        width="24"
        height="24"
        stroke-width="0"
        fill="#ccc"
        class="absolute right-2 top-1/2 -translate-y-1/2 cursor-pointer focus:outline-none"
        tabindex="-1"
      >
        <path d="M12 17.414 3.293 8.707l1.414-1.414L12 14.586l7.293-7.293 1.414 1.414L12 17.414z" />
      </svg>

      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "h-full rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym focus:ring-2	",
              "phx-no-feedback:transparent phx-no-feedback:focus:border-complementarym",
              @errors == [] && "",
              @errors != [] && " ring-rose-400  focus:ring-rose-400"
            ]
        }
        {@rest}
      />
      <.label for={@id} class="placeholder"><%= @label %></.label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "number"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form w-full h-full">
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym 	h-full p-0 md:p-2 sm:p-0 sm:pt-2 sm:pb-2 ",
              "phx-no-feedback:transparent phx-no-feedback:focus:border-complementarym text-sm sm:text-base p-1 sm:p-4",
              @errors == [] && "",
              @errors != [] && " ring-rose-400  focus:ring-rose-400"
            ]
        }
        {@rest}
      />
      <.label for={@id} class="placeholder"><%= @label %></.label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # Comment Input
  def input(%{type: "comment"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form w-full h-full">
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        style="height: 40px; padding-right: 44px; padding-left: 12px; overflow: hidden"
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "rounded-full border-greyfriend2 border-2 relative text-sm leading-4	"
            ]
        }
        {@rest}
      />
      <.label for={@id} class="placeholder"><%= @label %></.label>
      <button phx-clic="submit" class="absolute right-2 m-auto">
        <.icon
          name="hero-arrow-right-circle"
          class="mt-0.5 h-9 w-9 flex-none text-primary cursor-pointer"
        />
      </button>
      <!-- <button type="submit" class="primary_button" phx-disable-with="Saving...">Post</button> --->
    </div>
    """
  end

  def input(%{type: "select_plain"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <input
        id={@id}
        name={@name}
        class="hidden rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym focus:ring-2	h-full w-full  text-greyfriend3 font-semibold"
        ,
      />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym focus:ring-2	h-full w-full  text-greyfriend3 font-semibold"
        ,
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="input-form w-full h-full">
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={
          [Map.get(assigns.rest, :class, "")] ++
            [
              "rounded-lg border-greyfriend2 border-2 focus:border-transparent focus:ring-complementarym focus:ring-2	h-full",
              "phx-no-feedback:transparent phx-no-feedback:focus:border-complementarym",
              @errors == [] && "",
              @errors != [] && " ring-rose-400  focus:ring-rose-400"
            ]
        }
        {@rest}
      />
      <.label for={@id} class="placeholder px-4"><%= @label %></.label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="placeholder">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <div
      class="text-right text-base font-medium leading-6 text-rose-600 phx-no-feedback:hidden "
      style="position: absolute; bottom: -3rem;"
    >
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def my_error(assigns) do
    ~H"""
    <div class="" style="position: absolute; top: 0; left: 0; z-index: 600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header
      style="font-size: 2rem;"
      class={[@actions != [] && "flex items-center justify-between gap-6", @class]}
    >
      <div>
        <h1
          class="text-lg font-semibold leading-8 text-zinc-800"
          style="margin-inline: auto; text-align: center; font-size: 1.6rem;"
        >
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="subtitle">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class=" px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal w-fit"><%= col[:label] %></th>
            <th :if={@action != []} class="relative p-0 pb-4 w-fit">
              <span class="sr-only"><%= gettext("Actions") %></span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500"><%= item.title %></dt>
          <dd class="text-zinc-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  @doc """
  An attempt to make a stepper component  with references to 
  https://verpex.com/blog/website-tips/a-css-only-responsive-stepper-component
  https://codepen.io/t_afif/pen/gOjJpeq
  """
  def stepper(assigns) do
    steps = ["Step A", "Step B", "Step Ctroen", "Step D "]
    assigns = Map.put(assigns, :steps, steps)

    ~H"""
    <ol class="stepper">
      <%= for {step, index} <- Enum.with_index(@steps) do %>
        <%= if index == 0 do %>
          <.stepper_step
            class="stepper_step active pr-6 cursor-pointer"
            id={"step"<> Integer.to_string(index)}
            step={step}
            index={index}
          >
          </.stepper_step>
        <% else %>
          <%= if index == length(@steps) -1 do %>
            <.stepper_step
              class="stepper_step  cursor-pointer"
              step={step}
              index={index}
              id={"step"<> Integer.to_string(index)}
            >
            </.stepper_step>
          <% else %>
            <.stepper_step
              class="stepper_step pr-6 cursor-pointer"
              step={step}
              index={index}
              id={"step"<> Integer.to_string(index)}
            >
            </.stepper_step>
          <% end %>
        <% end %>
      <% end %>
    </ol>
    """
  end

  defp stepper_step(assigns) do
    ~H"""
    <li
      id={@id}
      class={@class}
      phx-click={
        JS.remove_class("active", to: ".stepper_step")
        |> JS.add_class("active", to: "#step#{@index}")
        |> JS.add_class("hidden", to: ".content_container")
        |> JS.remove_class("hidden", to: "#content-#{@index}")
      }
    >
    </li>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(MehungryWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MehungryWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
