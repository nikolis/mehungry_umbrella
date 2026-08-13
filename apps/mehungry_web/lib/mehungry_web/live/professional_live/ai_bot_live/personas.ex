defmodule MehungryWeb.AiBotLive.Personas do
  @moduledoc """
  Admin CRUD for AI-bot personas — the reusable authoring voices
  (grandma, tavern, dietologist…) referenced by recipe setups.
  """
  use MehungryWeb, :live_view

  alias Mehungry.AI.Bot
  alias Mehungry.AI.Bot.Persona

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:personas, Bot.list_personas())
     |> assign(:form, nil)
     |> assign(:page_title, "AI Bot Personas")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :form, nil)

  defp apply_action(socket, :new, _params) do
    assign(socket, :form, to_form(Bot.change_persona(%Persona{})))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    persona = Bot.get_persona!(id)
    assign(socket, :form, to_form(Bot.change_persona(persona)))
  end

  @impl true
  def handle_event("validate", %{"persona" => params}, socket) do
    changeset =
      case socket.assigns.live_action do
        :new -> Bot.change_persona(%Persona{}, params)
        :edit -> Bot.change_persona(socket.assigns.form.source.data, params)
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"persona" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Bot.create_persona(params)
        :edit -> Bot.update_persona(socket.assigns.form.source.data, params)
      end

    case result do
      {:ok, _persona} ->
        {:noreply,
         socket
         |> assign(:personas, Bot.list_personas())
         |> put_flash(:info, "Persona saved.")
         |> push_patch(to: ~p"/professional/ai-bot/personas")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Bot.get_persona!() |> Bot.delete_persona()

    {:noreply,
     socket
     |> assign(:personas, Bot.list_personas())
     |> put_flash(:info, "Persona deleted.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-xl font-bold text-white">Personas</h1>
        <p class="text-sm text-slate-400 mt-0.5">
          Reusable authoring voices — grandma, tavern, dietologist… Bound to a place and
          ingredients by a <.link navigate={~p"/professional/ai-bot/setups"} class="text-primary-400 hover:underline">Recipe Setup</.link>.
        </p>
      </div>
      <.link
        patch={~p"/professional/ai-bot/personas/new"}
        class="flex items-center gap-1 px-3 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium transition-colors"
      >
        <.icon name="hero-plus" class="h-4 w-4" /> New Persona
      </.link>
    </div>

    <div class="flex gap-6">
      <div class="w-96 flex-shrink-0 space-y-2">
        <div
          :for={persona <- @personas}
          class="bg-slate-800 border border-slate-700/60 rounded-xl p-4 group"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="font-semibold text-white text-sm flex items-center gap-2">
                {persona.name}
                <span
                  :if={persona.uses_hashtags}
                  class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-sky-500/20 text-sky-300 border border-sky-500/30"
                >
                  #hashtags
                </span>
                <span
                  :if={!persona.active}
                  class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-slate-700/50 text-slate-500 border border-slate-600/40"
                >
                  Off
                </span>
              </div>
              <div :if={persona.description} class="text-xs text-slate-400 mt-0.5">
                {persona.description}
              </div>
              <div class="text-[11px] text-slate-500 mt-1 line-clamp-2">{persona.voice_prompt}</div>
            </div>
          </div>
          <div class="flex gap-1 mt-3 opacity-0 group-hover:opacity-100 transition-opacity">
            <.link
              patch={~p"/professional/ai-bot/personas/#{persona.id}/edit"}
              class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-white hover:bg-slate-700 text-xs transition-colors"
            >
              <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Edit
            </.link>
            <button
              phx-click="delete"
              phx-value-id={persona.id}
              data-confirm="Delete this persona?"
              class="flex items-center gap-1 px-2 py-1 rounded-md text-slate-400 hover:text-red-400 hover:bg-red-500/10 text-xs transition-colors"
            >
              <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete
            </button>
          </div>
        </div>
        <p :if={@personas == []} class="text-sm text-slate-500">No personas yet.</p>
      </div>

      <div :if={@form} class="flex-1 min-w-0">
        <div class="bg-slate-800 border border-slate-700/60 rounded-xl p-6">
          <h2 class="text-base font-semibold text-white mb-5">
            {if @live_action == :new, do: "New Persona", else: "Edit Persona"}
          </h2>
          <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-xs text-slate-400 mb-1">Name</label>
              <.input field={@form[:name]} type="text" placeholder="e.g. Village Grandma" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Archetype (optional)</label>
              <.input field={@form[:archetype]} type="text" placeholder="e.g. grandmother" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Short description (optional)</label>
              <.input field={@form[:description]} type="text" class={input_class()} />
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Voice prompt</label>
              <.input
                field={@form[:voice_prompt]}
                type="textarea"
                rows="7"
                placeholder="You are a grandmother in a mountain village. You cook from what the garden and the season give you, you measure by feel and memory rather than grams, and you speak plainly and warmly about food…"
                class={input_class()}
              />
              <p class="text-[11px] text-slate-500 mt-1">
                Written in the second person — this becomes the character's identity in the
                generation prompt and the final rewrite.
              </p>
            </div>
            <div>
              <label class="block text-xs text-slate-400 mb-1">Default origin (optional)</label>
              <.input field={@form[:default_origin]} type="text" placeholder="e.g. a mountain village in Crete" class={input_class()} />
            </div>
            <label class="flex items-center gap-2 text-sm text-slate-300">
              <.input field={@form[:uses_hashtags]} type="checkbox" />
              Uses hashtags (folksy voices usually should not)
            </label>
            <label class="flex items-center gap-2 text-sm text-slate-300">
              <.input field={@form[:active]} type="checkbox" /> Active
            </label>
            <div class="flex items-center gap-2 pt-2">
              <button type="submit" class="px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 text-white text-sm font-medium">
                Save
              </button>
              <.link patch={~p"/professional/ai-bot/personas"} class="px-4 py-2 rounded-lg text-slate-400 hover:text-white text-sm">
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp input_class,
    do:
      "w-full bg-slate-700 border border-slate-600 rounded-lg text-white text-sm px-3 py-2 focus:border-primary-500 focus:outline-none"
end
