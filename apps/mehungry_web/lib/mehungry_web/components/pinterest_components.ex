defmodule MehungryWeb.PinterestComponents do
  @moduledoc """
  Shared UI for the Pinterest board/pin flow, used by both the user-facing recipe
  pin component (`MehungryWeb.SocialMediaPostComponent`) and the admin bot social
  page (`MehungryWeb.AiBotLive.SocialAccounts`).

  `board_card/1` renders a board richly (cover thumbnail + pin count + privacy
  badge) from the fields already present in the `GET /boards` response, so no
  extra API calls are needed. `board_form/1` is the create-board form with an
  in-flight "Creating…" state; both surfaces submit the `create_pinterest_board`
  event so the form is identical.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: MehungryWeb.Endpoint,
    router: MehungryWeb.Router

  use Phoenix.Component

  import MehungryWeb.CoreComponents, only: [icon: 1]

  @doc """
  Visual card for a single Pinterest board. Purely presentational — wrap it in a
  button when it needs to be selectable.
  """
  attr :board, :map, required: true
  attr :selected, :boolean, default: false

  def board_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 w-full p-2.5 rounded-xl border transition",
      if(@selected,
        do: "bg-paprika/20 border-paprika ring-1 ring-paprika",
        else: "border-ink-panel2 bg-black/20 hover:border-parchment-dim"
      )
    ]}>
      <div class="w-12 h-12 rounded-lg overflow-hidden bg-ink-panel2 flex-shrink-0 flex items-center justify-center">
        <%= if cover_url(@board) do %>
          <img src={cover_url(@board)} alt="" class="w-full h-full object-cover" />
        <% else %>
          <.icon name="hero-rectangle-stack" class="h-5 w-5 text-parchment-dim" />
        <% end %>
      </div>
      <div class="min-w-0 flex-1">
        <p class="text-sm font-semibold text-parchment truncate">{@board["name"]}</p>
        <p class="text-xs text-parchment-dim">{pin_count_label(@board)}</p>
      </div>
      <span class={[
        "inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold border flex-shrink-0",
        privacy_badge_class(@board["privacy"])
      ]}>
        {privacy_label(@board["privacy"])}
      </span>
      <%= if @selected do %>
        <.icon name="hero-check-circle-solid" class="h-5 w-5 text-paprika flex-shrink-0" />
      <% end %>
    </div>
    """
  end

  @doc """
  Create-board form (name / description / privacy). Submits the
  `create_pinterest_board` event; pass `target` for a live_component (`@myself`)
  or omit it inside a LiveView. The submit button shows a "Creating…" in-flight
  state via `phx-disable-with`.
  """
  attr :target, :any, default: nil
  attr :error, :string, default: nil

  def board_form(assigns) do
    ~H"""
    <form
      phx-submit="create_pinterest_board"
      phx-target={@target}
      class="space-y-3 p-4 rounded-xl bg-black/20 border border-ink-panel2"
    >
      <p class="text-sm font-semibold text-parchment flex items-center gap-1.5">
        <.icon name="hero-plus-circle" class="h-4 w-4 text-paprika-soft" /> Create a new board
      </p>
      <input
        type="text"
        name="board[name]"
        required
        maxlength="180"
        placeholder="Board name"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 placeholder-parchment-dim focus:border-paprika focus:outline-none"
      />
      <textarea
        name="board[description]"
        rows="2"
        maxlength="500"
        placeholder="Description (optional)"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 placeholder-parchment-dim focus:border-paprika focus:outline-none"
      ></textarea>
      <select
        name="board[privacy]"
        class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg text-parchment text-sm px-3 py-2 focus:border-paprika focus:outline-none"
      >
        <option value="PUBLIC">Public</option>
        <option value="SECRET">Secret</option>
      </select>
      <%= if @error do %>
        <p class="text-xs text-red-400">{@error}</p>
      <% end %>
      <div class="flex justify-end">
        <button
          type="submit"
          phx-disable-with="Creating…"
          class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-bold transition-colors disabled:opacity-60 disabled:cursor-wait"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> Create Board
        </button>
      </div>
    </form>
    """
  end

  defp cover_url(board) do
    case board["media"] do
      %{"image_cover_url" => url} when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  defp pin_count_label(board) do
    case board["pin_count"] do
      count when is_integer(count) -> "#{count} #{if count == 1, do: "pin", else: "pins"}"
      _ -> "Board"
    end
  end

  defp privacy_label(privacy) do
    case privacy do
      "SECRET" -> "Secret"
      "PROTECTED" -> "Protected"
      _ -> "Public"
    end
  end

  defp privacy_badge_class(privacy) do
    case privacy do
      "SECRET" -> "bg-amber-500/15 text-amber-300 border-amber-500/30"
      "PROTECTED" -> "bg-amber-500/15 text-amber-300 border-amber-500/30"
      _ -> "bg-emerald-500/15 text-emerald-300 border-emerald-500/30"
    end
  end
end
