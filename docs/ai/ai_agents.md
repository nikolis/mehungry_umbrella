# AI Agents — How They Work

Everything AI-related lives in `apps/mehungry/lib/mehungry/ai/`. This document explains each piece in plain terms — what it does, how it operates, why it was built that way — with excerpts from the actual code. All snippets below are copied from the codebase (trimmed with `# …` where irrelevant).

## The Big Picture

```
                        ┌────────────────────────────────────┐
                        │  Entry points                      │
                        │  • LiveViews (user clicks a button)│
                        │  • Oban workers (background jobs)  │
                        └───────────────┬────────────────────┘
                                        │
              ┌─────────────────────────┼──────────────────────────┐
              │                         │                          │
   ┌──────────▼─────────┐   ┌───────────▼──────────┐   ┌───────────▼──────────┐
   │  Agents (tool-use  │   │  Single-shot utils   │   │  Non-Anthropic       │
   │  loops)            │   │  RecipeTranslator    │   │  ImageGenerator      │
   │  RecipeAgent       │   │  IngredientTranslator│   │  (OpenAI gpt-image-1)│
   │  MealPlanAgent     │   │                      │   │  EmbeddingClient     │
   │  NutritionistAgent │   │                      │   │  (OpenAI embeddings) │
   └──────────┬─────────┘   └───────────┬──────────┘   └──────────────────────┘
              │                         │
        ┌─────▼─────┐                   │
        │ AI.Agent  │  generic loop     │
        └─────┬─────┘                   │
              │                         │
        ┌─────▼─────────────────────────▼─────┐
        │ AI.Client — one HTTP client for the │
        │ Anthropic Messages API              │
        └─────────────────────────────────────┘
```

Two layers of infrastructure, three real agents, and a handful of single-shot utilities.

---

## Layer 1: `AI.Client` (`ai/client.ex`)

**What it is:** The single HTTP client every Anthropic call goes through. Nothing else in the app should call the Anthropic API directly.

```elixir
@api_url "https://api.anthropic.com/v1/messages"
@default_model "claude-haiku-4-5-20251001"
@default_max_tokens 2048
@timeout_ms 90_000
@max_retries 3
@retry_base_ms 1_000
```

The retry logic is deliberately narrow — only 529 (Anthropic "overloaded") and timeouts are retried, because those are the only errors where retrying can help. A 400 will fail the same way every time:

```elixir
defp do_request(api_key, params, attempt) do
  case HTTPoison.post(@api_url, build_body(params), headers(api_key), recv_timeout: @timeout_ms) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
      parse_response(body)

    {:ok, %HTTPoison.Response{status_code: 529}} ->
      delay = round(@retry_base_ms * :math.pow(2, attempt))
      Logger.warning("AI.Client: rate limited, retrying in #{delay}ms (attempt #{attempt + 1})")
      Process.sleep(delay)
      do_request(api_key, params, attempt + 1)

    {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
      Logger.warning("AI.Client: API error #{code}: #{body}")
      {:error, "API returned status #{code}"}

    {:error, %HTTPoison.Error{reason: :timeout}} when attempt < @max_retries - 1 ->
      # …retry…
```

**Why it exists:** Before this, AI modules made raw HTTPoison calls, each duplicating auth, retry, and parse logic. Centralizing means retry policy and the `anthropic-version` header live in one place.

**Tradeoff:** `Process.sleep` blocks the calling process during backoff. That's acceptable because AI calls run inside Oban workers or `Task.async` — never directly in a LiveView process.

## Layer 2: `AI.Agent` (`ai/agent.ex`)

**What it is:** A generic "tool-use loop" — the engine all three agents run on. The whole thing is ~150 lines; this is its heart:

```elixir
defp loop(messages, handler, ctx, req_base, iteration, max_iter) do
  request = Map.put(req_base, :messages, messages)

  case Mehungry.AI.Client.request(request) do
    {:ok, %{stop_reason: "end_turn", content: content}} ->
      {:ok, Mehungry.AI.Client.text_from(%{content: content})}

    {:ok, %{stop_reason: "tool_use", content: content}} ->
      tool_results = dispatch_tools(content, handler, ctx)

      new_messages =
        messages ++
          [%{role: "assistant", content: content}] ++
          [%{role: "user", content: tool_results}]

      loop(new_messages, handler, ctx, req_base, iteration + 1, max_iter)
    # …max_tokens and error clauses…
  end
end
```

The caller supplies tools as plain maps and a handler function. Tool crashes are caught and **fed back to the model** as an error result instead of killing the job — the model can then retry with different input:

```elixir
result =
  try do
    handler.(name, input, ctx)
  rescue
    e ->
      Logger.error("AI.Agent: tool #{name} raised: #{Exception.message(e)}")
      %{error: "Tool execution failed: #{Exception.message(e)}"}
  end

%{type: "tool_result", tool_use_id: id, content: Jason.encode!(result)}
```

**Key decisions:**
- **The handler is just a function** (`fn tool_name, input, context -> result end`), not a behaviour or GenServer. The loop stays tiny and each agent owns its tools entirely.
- **`max_iterations` (default 10) is a hard cap**, and hitting it is an *error* (`{:error, :max_iterations_reached}`), not a partial success. Better to fail loudly than persist a half-finished result.

---

## The Three Agents (`ai/agents/`)

All three share the design idea that matters most in this codebase:

> **The database is the source of truth, and the agent must prove its output against it before anything is saved.** Each agent gets a `submit_*` tool that validates every ID against the real database. Invalid IDs come back as error messages; the model corrects itself and resubmits. The model is never trusted to produce valid foreign keys — LLMs happily invent plausible-looking numeric IDs.

A second shared mechanism: the loop returns *text*, but the actual result is threaded back through the **accumulator**. `Agent.run/6` takes an initial accumulator, the handler returns `{result, new_acc}`, and `run/6` returns `{:ok, text, final_acc}`. The `submit_*` handler writes its validated output into the accumulator's `:submitted` slot; if the loop ends with `:submitted` still `nil`, that's detected and treated as failure. (This replaced an earlier process-dictionary smuggle — see improvement #7 below, now done.)

```elixir
# RecipeAgent.run_once/3
acc = Map.merge(context, %{offered: %{}, submitted: nil})

result = Agent.run(system_prompt(), "Create a recipe from this description: #{description}",
                   tool_defs(), &handle_tool/3, acc,
                   telemetry_metadata: %{agent: "recipe"},
                   model: @model, max_tokens: 8192, max_iterations: 14)

case result do
  {:ok, _text, %{submitted: nil}} -> {:error, :no_submit}
  {:ok, _text, %{submitted: saved}} -> saved
  {:error, reason} -> {:error, reason}
end
```

The same accumulator carries **provenance** state: `:offered` records every
id→name the search/create tools handed the model this run, so `submit_*` can
reject any id the model never actually received. All three agents now do this —
`RecipeAgent` for ingredient ids, `MealPlanAgent`/`NutritionistAgent` for
recipe ids.

### 1. `RecipeAgent` — natural language → complete recipe

**Used by:** the AI bot pipeline (`DailyRecipeGenerationWorker`, 2am UTC daily) and user-facing generation in the create-recipe LiveView (via `RecipeGenerator.run/1`).

**Tools it gives the model:**

| Tool | What it does |
|---|---|
| `search_ingredient` | Fuzzy-searches the ingredient DB, returns up to 3 candidates with their valid measurement units |
| `create_ingredient` | Adds a missing ingredient — real USDA FDC API first, AI-estimated nutrition as fallback |
| `submit_recipe` | Validates all ingredient/unit IDs, polishes prose, saves the result |

The system prompt spells out the workflow and bans invented IDs:

```
1. Identify all ingredients the recipe needs …
2. For EACH ingredient, call search_ingredient — inspect the returned candidates …
3. If search_ingredient returns no results …, call create_ingredient …
4. Draft the recipe using ONLY ingredient_id and measurement_unit_id values from
   your tool results — never invent or guess numeric IDs
5. Call submit_recipe with the complete recipe to validate and save it
6. If submit_recipe returns errors, fix ONLY the reported invalid IDs and resubmit
```

**Search results are cleaned before the model sees them.** USDA names are weird — searching "eggs" can rank "Fish, herring, eggs" above "Eggs, whole, raw", and "egg yolk powder" above whole eggs. Three helpers fix this deterministically rather than hoping the model is careful:

```elixir
defp handle_tool("search_ingredient", %{"name" => name}, %{gram_unit: gram_unit}) do
  top =
    Food.IngredientSearch.search(name)
    |> rerank_by_name(name)            # first-word Jaro similarity floats "Eggs, whole" up
    |> filter_by_name_relevance(name)  # drops candidates whose first word matches nothing
    |> reject_partial_variants(name)   # drops yolk/powder/dried forms not asked for
    |> Enum.take(3)
```

```elixir
@partial_indicators ~w(yolk white albumen powder dried dehydrated freeze extract concentrate)

defp reject_partial_variants(ingredients, search_term) do
  search_lower = String.downcase(search_term)

  Enum.reject(ingredients, fn ing ->
    ing_lower = String.downcase(ing.name)

    Enum.any?(@partial_indicators, fn indicator ->
      String.contains?(ing_lower, indicator) and not String.contains?(search_lower, indicator)
    end)
  end)
end
```

**Tradeoff:** `@partial_indicators` is a hardcoded heuristic and can occasionally hide a legitimate match ("dried" is dropped unless the user typed "dried") — but a wrong ingredient in a published recipe is worse than a re-search.

**Validation is per-ID and returns actionable errors.** `submit_recipe` checks that every ingredient exists and every unit actually belongs to that ingredient, then tells the model exactly which IDs are valid:

```elixir
if unit_id in valid_ids do
  []
else
  [
    "measurement_unit_id #{unit_id} is invalid for ingredient_id #{ing_id}. " <>
      "Valid unit_ids: #{inspect(Enum.uniq(valid_ids))}"
  ]
end
```

**Two models, split by job.** The tool loop runs on **Haiku** (cheap, fast, good at structured tool calling). After validation passes, one extra call to **Sonnet** rewrites only the user-visible text:

```elixir
@model "claude-haiku-4-5-20251001"     # drives the tool loop
@writer_model "claude-sonnet-4-6"      # polishes title/description/steps/hashtags
```

The polish step is **best-effort** — a plain recipe beats no recipe:

```elixir
{:error, reason} ->
  Logger.warning("RecipeAgent: prose polish failed (#{inspect(reason)}), using draft")
  recipe_input
```

**Ingredient creation prefers real data.** `create_ingredient` queries the USDA FDC API first and only falls back to AI-estimated nutrition, tagging each row with its provenance:

```elixir
{json_result, data_source} =
  case Mehungry.FoodData.Usda.FdcClient.lookup(name) do
    {:ok, json} ->
      {{:ok, json}, "usda_fdc"}

    {:error, reason} ->
      Logger.info("RecipeAgent: USDA FDC lookup failed (#{reason}), falling back to AI estimation")
      {generate_usda_json_for(name), "ai_estimate"}
  end

# …
Mehungry.FoodData.Usda.FoodParser.get_ingredients_from_json_body(json_string, data_source)
```

**Tradeoff:** AI-estimated nutrition is approximate, but the alternative is a recipe that fails because one exotic ingredient is missing — and the `data_source` tag keeps estimates auditable.

One quirk worth knowing: the gram unit is looked up by the literal name `"grammar"` (`Food.get_measurement_unit_by_name("grammar")`) — a legacy naming artifact of the units table. Renaming that unit would silently remove the gram option from every agent run.

### 2. `MealPlanAgent` — 7-day meal plan for a user

**Used by:** the calendar LiveView (via `MealPlanGenerator.run/4`), quota-gated by subscription tier. The LiveView checks quota first, runs the pipeline in a `Task` so the socket stays responsive, and records usage only on success:

```elixir
# calendar_live/index.ex
case Mehungry.Subscriptions.check_quota(user.id, "meal_plan") do
  :ok ->
    task =
      Task.async(fn ->
        Mehungry.AI.MealPlanGenerator.run(prompt, recipes, start_date, user.id)
      end)
    # assigns :ai_plan_generating, :ai_plan_task_ref …

  {:error, :quota_exceeded} ->
    {:noreply, assign(socket, :ai_quota_exceeded, true)}
end
```

**Tools:** `get_recent_meals` (last 21 days of history, so the plan avoids repeats), `search_catalog` (semantic vector search over the user's recipes), `submit_plan` (validate + persist all 21 entries).

**Semantic search instead of prompt stuffing.** The legacy generator inlined up to 80 recipes as text into the prompt. The agent instead searches by meaning:

```elixir
defp handle_tool("search_catalog", %{"query" => query}, %{user_id: user_id}) do
  recipes =
    RecipeVectorSearch.search(query, user_id: user_id, limit: 20)
    |> Enum.map(fn r ->
      %{id: r.id, title: r.title, difficulty: r.difficulty || 1, servings: r.servings || 2}
    end)
```

`RecipeVectorSearch` (`search/recipe_vector_search.ex`) embeds the query via OpenAI and orders by pgvector cosine distance, with a full-text-search fallback if embedding fails:

```elixir
case EmbeddingClient.embed(query_text) do
  {:ok, vector} ->
    vector_search(vector, user_id, limit, exclude_ids)

  {:error, reason} ->
    Logger.warning("RecipeVectorSearch: embedding failed (#{reason}), falling back to FTS")
    fts_fallback(query_text, user_id, limit)
end

# vector_search/4:
from r in Recipe,
  where: not is_nil(r.embedding),
  order_by: fragment("embedding <=> ?", ^pg_vector),
  limit: ^limit,
  select: %{id: r.id, title: r.title, difficulty: r.difficulty, servings: r.servings}
```

**`submit_plan` validation** checks four things and reports each failure in words the model can act on: recipe IDs must be in the user's catalog, dates inside the 7-day window, slots exactly `Breakfast/Lunch/Dinner`, and no `(date, slot)` pair twice:

```elixir
defp check_duplicate_slots(entries) do
  entries
  |> Enum.group_by(fn e -> {e["date"], e["slot"]} end)
  |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
  |> Enum.map(fn {{date, slot}, _} -> "Duplicate slot: #{date} #{slot}" end)
end
```

**Partial persistence is allowed at the save step** — entries that pass validation but still fail on insert are counted as skipped rather than rolling back the whole plan. A plan with 19/21 meals is more useful than nothing:

```elixir
{created, skipped} = persist_plan(entries, user_id)
# result threaded back via the accumulator, not the process dictionary:
{%{success: true, created: length(created), skipped: skipped, message: "…"},
 %{acc | submitted: {:ok, created, skipped}}}
```

Meal times are fixed by convention rather than asked of the model:

```elixir
defp slot_time("Breakfast"), do: ~T[08:00:00]
defp slot_time("Lunch"), do: ~T[13:00:00]
defp slot_time("Dinner"), do: ~T[19:00:00]
```

### 3. `NutritionistAgent` — 7-day plan drafted *for a client* by a professional

**Used by:** `NutritionistAgentWorker` (Oban, `ai_agents` queue), triggered from the nutritionist's client-detail LiveView. Pro-tier feature.

Same skeleton as `MealPlanAgent`, with three differences that matter:

**1. Two-party context.** Recipes come from the *professional's* catalog; the plan is persisted to the *client's* account:

```elixir
defp do_handle_tool("submit_plan", %{"entries" => entries, "rationale" => rationale}, context) do
  %{client_id: client_id, start_date: start_date, professional_id: professional_id} = context

  valid_ids =
    Food.list_user_recipes(professional_id)   # professional's recipes…
    |> MapSet.new(& &1.id)
  # …
  {created, skipped} = persist_entries(entries, client_id)   # …client's meals
```

**2. More input tools** — `get_client_summary` and `get_ratings` in addition to meal history, so the plan reflects what the client actually liked. `submit_plan` also *requires* a `rationale` ("2–3 sentence professional note explaining the plan choices") — making the model justify the plan doubles as a light quality check and gives the nutritionist something to show the client.

**3. Live progress streaming.** The agent accepts an `on_event` callback that wraps every tool call; the Oban worker turns tool names into human-readable labels and broadcasts them over PubSub, so the nutritionist watches the agent work instead of staring at a spinner:

```elixir
# nutritionist_agent.ex — the agent stays transport-agnostic
handler = fn name, input, ctx ->
  on_event.({:tool_call, name})
  result = do_handle_tool(name, input, ctx)
  on_event.({:tool_result, name, result})
  result
end
```

```elixir
# nutritionist_agent_worker.ex — the worker owns the transport
@tool_labels %{
  "get_client_summary" => "Reading client profile…",
  "get_recent_meals" => "Checking recent meal history…",
  "get_ratings" => "Reviewing meal ratings…",
  "search_recipes" => "Searching recipe catalog…",
  "submit_plan" => "Validating and creating meal plan…"
}

on_event = fn
  {:tool_call, name} ->
    broadcast(topic, {:step, Map.get(@tool_labels, name, "Working…")})
  {:tool_result, _name, _result} -> :ok
end
```

**Why a callback and not PubSub inside the agent:** the agent stays pure and testable; topic naming and event shapes are the worker's concern.

It runs with `max_iterations: 16` (vs 10–12 for the others) because it has more information-gathering tools to call, and `max_attempts: 1` in Oban — retrying a whole agent run after a partial failure could create duplicate meals for the client.

---

## Single-Shot Utilities (no tool loop)

Plain "one prompt → parse JSON" calls. A tool loop would be overkill: these tasks have no decisions to make, only a transformation.

| Module | Model | What it does |
|---|---|---|
| `RecipeTranslator` | Sonnet | Translates title/description/steps to a target language (en/el today). Enforces same step count; preserves times, quantities, temperatures. |
| `IngredientTranslator` | Sonnet | Batch-translates USDA ingredient names to everyday Greek kitchen names. |
| `MealPlanGenerator` legacy path | Haiku | Old single-shot plan generation — now only the fallback for `MealPlanAgent`. |
| `RecipeGenerator` legacy path | Sonnet | Old multi-phase recipe pipeline — now only the fallback for `RecipeAgent`. |

**Why Sonnet for translation but Haiku for agent loops?** Translation quality *is* the product of those modules — a clumsy Greek ingredient name is immediately visible to users — and the calls are infrequent and batched. Agents mostly do structured tool calling, where Haiku is sufficient and much cheaper.

`IngredientTranslator` is a good example of domain-specific prompting — it doesn't ask for "translation", it asks for what a Greek home cook would actually write, with few-shot examples:

```
Your task is to produce the name a Greek home cook would use when writing a recipe — the same
vocabulary found on popular Greek recipe sites like akispetretzikis.com, gastronomos.gr, and argiro.gr.
…
{
  "Chicken, broilers or fryers, breast, meat only, cooked, roasted": "στήθος κοτόπουλου",
  "Oil, olive, salad or cooking": "ελαιόλαδο",
  "Tomatoes, red, ripe, raw, year round average": "ντομάτα",
  …
}
```

All JSON-returning prompts share the same defensive parsing — strip markdown fences before decoding, because models add them even when told not to:

```elixir
text
|> String.trim()
|> String.replace(~r/```json\s*/i, "")
|> String.replace(~r/```\s*/, "")
|> String.trim()
|> Jason.decode()
```

This exact snippet appears (with small variations) in `RecipeAgent`, `RecipeGenerator`, `MealPlanGenerator`, `RecipeTranslator`, and `IngredientTranslator` — see Improvements below.

## Non-Anthropic Pieces

**`ImageGenerator`** — OpenAI `gpt-image-1` (Anthropic doesn't offer image generation). A fixed food-photography style is appended to every prompt, and recipe hashtags are stripped first so they don't end up rendered in the image:

```elixir
defp build_prompt(title, description) do
  clean_desc = description |> String.replace(~r/#\S+/, "") |> String.trim()

  "Professional food photography of #{title}. #{clean_desc}. " <>
    "Plated beautifully on a rustic wooden or marble surface, natural side lighting, " <>
    "shallow depth of field, garnished and styled. Warm appetizing tones. " <>
    "No text overlays, no watermarks, photorealistic."
end
```

`RecipeImageWorker` runs it, uploads the JPEG to S3, and writes `image_url` back to the recipe — skipping recipes that already have an image.

**`EmbeddingClient`** — OpenAI `text-embedding-3-small`, 1536-dim vectors stored in `recipes.embedding` (pgvector). `RecipeEmbeddingWorker` builds the text to embed from title + description + cuisine + ingredient names + hashtags, and is triggered on recipe create/update (plus a `enqueue_all/0` backfill callable from iex). Full breakdown in **Recipe Embeddings & Semantic Search** below.

## Recipe Embeddings & Semantic Search

Three pieces make up the write side of semantic search: an OpenAI HTTP client, the Oban worker that writes embeddings, and the pgvector column they're written to. The read side (`RecipeVectorSearch`) was already introduced under `MealPlanAgent` above — this section is the full picture. It also documents a schema gap that used to make the write side fail on every run (now fixed — see below).

### `AI.EmbeddingClient` (`ai/embedding_client.ex`)

**What it is:** A single-purpose HTTP client for OpenAI's embeddings endpoint — the only place in the app that talks to `text-embedding-3-small`.

```elixir
@api_url "https://api.openai.com/v1/embeddings"
@model "text-embedding-3-small"

def embed(text) when is_binary(text) do
  api_key = System.get_env("OPENAI_API_KEY")

  if is_nil(api_key) or api_key == "" do
    {:error, "OPENAI_API_KEY not set"}
  else
    body = Jason.encode!(%{model: @model, input: text})
    # …POST, then match on {"data" => [%{"embedding" => embedding} | _]}…
```

It takes one string and returns `{:ok, [float]}` (a 1536-element list) or `{:error, reason}`. Every failure mode is handled explicitly and logged: missing API key, non-200 HTTP status, JSON decode failure, an unexpected response shape (no `data[0].embedding`), and a transport-level `HTTPoison.Error`.

**How it differs from `AI.Client`:**
- **No retries.** `AI.Client` backs off on 529/timeout for Anthropic; `EmbeddingClient` fails immediately on any error and leaves retry policy entirely to the caller (in practice, Oban's own attempt/backoff mechanism on `RecipeEmbeddingWorker`).
- **Reads the API key from `System.get_env/1` directly on every call**, rather than from `Application` config the way the Anthropic key is wired up via `runtime.exs` (see CLAUDE.md's `ANTHROPIC_API_KEY` entry) — functionally fine today, just a different pattern from the rest of the AI layer.
- **One string per call, no batching.** OpenAI's embeddings endpoint accepts an array of inputs in a single request; this client always sends exactly one (see Optimization item 4 below — `enqueue_all/0` fires one HTTP call per recipe rather than batching).

### `RecipeEmbeddingWorker` (`oban_workers/recipe_embedding_worker.ex`)

**What it is:** the Oban job that turns a recipe into text, embeds it, and writes the vector back onto the row.

```elixir
use Oban.Worker, queue: :default, max_attempts: 3

def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do
  recipe =
    Food.get_recipe_no_caching!(recipe_id)
    |> Repo.preload(recipe_ingredients: :ingredient, recipe_hashtags: :hashtag)

  text = build_text(recipe)

  case EmbeddingClient.embed(text) do
    {:ok, vector} ->
      Repo.update_all(
        from(r in Recipe, where: r.id == ^recipe_id),
        set: [embedding: Pgvector.new(vector)]
      )
      # …Logger.info("embedding stored for recipe #{recipe_id}")…
```

**Deliberately bypasses the cache and the changeset.** It calls `Food.get_recipe_no_caching!/1` rather than the normal cached lookup — an embedding job shouldn't read a possibly-stale cached struct, and shouldn't populate `:recipes_cache` just to read text fields. It writes with `Repo.update_all/2` instead of a changeset, appropriate for a single-column, no-validation write — but that choice is exactly where the bug below bites.

**The text it embeds** is deliberately narrow — the fields useful for "what is this recipe about", not the whole record:

```elixir
[
  recipe.title,
  recipe.description,
  recipe.cousine,
  if(ingredients != [], do: Enum.join(ingredients, ", ")),
  if(hashtags != [], do: Enum.join(hashtags, ", "))
]
|> Enum.reject(&(is_nil(&1) or &1 == ""))
|> Enum.join(". ")
```

**Two entry points, one backfill:**

| Function | Called from | Purpose |
|---|---|---|
| `enqueue/1` | `Food.create_recipe/1`, `Food.update_recipe/2` (`food.ex:979`, `food.ex:1138`) | Embed a single recipe right after it's saved |
| `enqueue_all/0` | Admin "Backfill Recipe Embeddings" button (`maintenance_live.ex`) | Find every recipe with `embedding IS NULL` and enqueue one job each |

```elixir
def enqueue_all do
  ids = Repo.all(from r in Recipe, where: is_nil(r.embedding), select: r.id)
  Enum.each(ids, &enqueue/1)
  length(ids)
end
```

### `recipes.embedding` — the pgvector column, and the schema-field bug that used to break writes

> **Fixed 2026-08-14.** `Mehungry.Food.Recipe` now declares `field :embedding, Pgvector.Ecto.Vector` (`food/schemas/recipe.ex`). The write path below no longer raises. This section is kept as the history + rationale; the one remaining action is a **backfill** (existing rows are still `NULL` — see the note at the end).

The column comes purely from a migration:

```elixir
# 20260622000001_add_pgvector_and_recipe_embeddings.exs
execute("CREATE EXTENSION IF NOT EXISTS vector")

alter table(:recipes) do
  add :embedding, :vector, size: 1536
end

execute("CREATE INDEX ON recipes USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)")
```

For a long time `Mehungry.Food.Recipe` had **no corresponding `field :embedding, ...`** in its `schema "recipes" do` block. That gap didn't break every query that touches the column — it broke exactly one, and it was the one that mattered:

| Usage | Where | Validated against schema fields? | Result (before fix) |
|---|---|---|---|
| `where: is_nil(r.embedding)` | `enqueue_all/0`, `Food.count_recipes_missing_embeddings/0` | No — bare column refs in `where`/`order_by` compile straight to SQL | Works |
| `order_by: fragment("embedding <=> ?", ...)` | `RecipeVectorSearch.vector_search/4` | No — raw fragment | Works |
| `Repo.update_all(query, set: [embedding: ...])` | `RecipeEmbeddingWorker.perform/1` | **Yes** — `update_all`'s `set:` keys are checked against `__schema__(:fields)` | **Raised** |

```
** (Ecto.QueryError) field `embedding` in `update` does not exist in schema Mehungry.Food.Recipe in query
```

So the one write path that actually stores an embedding — `RecipeEmbeddingWorker.perform/1` — raised every single time it ran. Oban retried it up to `max_attempts: 3`, then marked the job `discarded`. The `Logger.info("... embedding stored ...")` line right after that `Repo.update_all` call never fired. Every recipe's `embedding` column stayed `NULL` — clicking "Backfill Recipe Embeddings" in the maintenance page enqueued jobs that all failed, and the "missing embeddings" counter never moved.

**Downstream effect on search (before the fix):** `RecipeVectorSearch.search/2` only falls back to full-text search when `EmbeddingClient.embed/1` itself errors (e.g. OpenAI is unreachable). Given a working OpenAI call, it embedded the *query* successfully, then ran `where: not is_nil(r.embedding)` against a table where that was true for zero rows, and returned `[]` — silently, without falling back. So `MealPlanAgent`'s `search_catalog` tool (and any other caller of `RecipeVectorSearch`) wasn't "degraded to full-text search"; it got nothing back from the vector path at all.

**The fix was one line** — declare the field the migration already created a column for:

```elixir
field :embedding, Pgvector.Ecto.Vector
```

(`Pgvector.Ecto.Vector` is the Ecto type the `pgvector` hex package — already a dependency, `mix.exs:69` — ships for exactly this case; `canonical_food.ex` already used the same field.) With it declared, `Repo.update_all`'s `set:` validation passes and the pipeline, write and read, works as originally designed.

> **Side effect of declaring the field:** `:embedding` is now loaded on every full-struct Recipe query (1536 floats each), including the LRU `:recipes_cache`. `canonical_food` accepts the same cost. If it ever shows up in hot-path read latency, scope it out with `select`/`Ecto.Query.exclude` on the cached reads.

### How the three pieces fit together

```
WRITE PATH (fixed 2026-08-14)
  Food.create_recipe/1 or update_recipe/2
        │
        ▼
  RecipeEmbeddingWorker.enqueue/1   (Oban, :default queue, max_attempts: 3)
        │
        ▼
  perform/1: preload ingredients+hashtags → build_text/1 → EmbeddingClient.embed/1 (OpenAI)
        │
        ▼
  Repo.update_all(set: [embedding: ...])   ✓ persists now that :embedding is a schema field
        │
        ▼
  recipes.embedding set for that row.  (Older rows stay NULL until a backfill runs.)

READ PATH
  MealPlanAgent "search_catalog" tool  /  any RecipeVectorSearch.search/2 caller
        │
        ▼
  EmbeddingClient.embed/1 (OpenAI, query text)   ✓ succeeds
        │
        ▼
  where: not is_nil(r.embedding), order_by: cosine distance
        │
        ▼
  rows within a newly-embedded catalog  (empty until the backfill fills historical rows)
```

**Remaining action — backfill.** The fix only makes *new* create/update writes succeed. Every recipe that predates the fix still has `embedding IS NULL`. Run the "Backfill Recipe Embeddings" button in the maintenance page (`RecipeEmbeddingWorker.enqueue_all/0`) once to embed the existing catalog; until then vector search only sees recipes touched since 2026-08-14.

## Fallback Strategy

Both public entry points keep the legacy pipeline as a safety net:

```elixir
# recipe_generator.ex
def run(description) do
  case Mehungry.AI.Agents.RecipeAgent.run(description) do
    {:ok, attrs, unmatched} ->
      {:ok, attrs, unmatched}

    {:error, reason} ->
      Logger.warning("RecipeAgent failed (#{inspect(reason)}), falling back to legacy pipeline")
      run_legacy(description)
  end
end
```

The legacy paths behave differently from the agents in one important way: instead of asking the model to fix invalid IDs, they **silently patch them after the fact**. `RecipeGenerator.validate_ingredients/2` drops hallucinated ingredients and swaps invalid unit IDs for the first valid one:

```elixir
if unit_id in valid_units do
  ri
else
  # Unit was hallucinated or belongs to a different ingredient — use first valid one
  Logger.warning("AI returned invalid unit_id #{inspect(unit_id)} for ingredient #{ing_id}, " <>
                   "replacing with #{inspect(List.first(valid_units))}")
  %{ri | "measurement_unit_id" => List.first(valid_units)}
end
```

That silent patching is exactly what the agents were built to eliminate (a recipe can end up measured in the wrong unit) — but as a *fallback* it's the right call: dumber and simpler, so a user request still succeeds when the agent path breaks.

**Tradeoff:** double the code to maintain, and a failed agent run pays for both paths. The intent is to delete the legacy paths once the agents prove reliable in production.

## How It All Runs (Oban)

Agent and image work runs on the `ai_agents` queue with **concurrency 2** — deliberately low so bursts don't hit Anthropic/OpenAI rate limits or run up costs. Cheaper supporting jobs run on `default` (concurrency 10).

| Worker | Queue | Attempts | Trigger | Calls |
|---|---|---|---|---|
| `DailyRecipeGenerationWorker` | ai_agents | 2 | Cron, 2am UTC daily | `RecipeAgent` per meal type |
| `NutritionistAgentWorker` | ai_agents | 1 | Nutritionist clicks "draft plan" | `NutritionistAgent` + PubSub progress |
| `RecipeTranslationWorker` | ai_agents | 3 | After recipe generation | `RecipeTranslator` |
| `RecipeImageWorker` | ai_agents | 2 | `Food.create_recipe/1` when no image | `ImageGenerator` + S3 upload |
| `RecipeEmbeddingWorker`¹ | default | 3 | Recipe create/update + backfill | `EmbeddingClient` |
| `IngredientTranslationWorker` | default | 3 | New ingredients; self-chaining | `IngredientTranslator` |

¹ Persists correctly since the `field :embedding` fix (2026-08-14); a one-time backfill is still needed for pre-fix rows — see **Recipe Embeddings & Semantic Search** above.

Two patterns worth copying:

**The daily worker fans out with bounded concurrency and is idempotent.** Each meal type is generated in parallel (max 2 at a time, matching the queue limit), already-generated recipes are skipped, and each recipe is persisted in a transaction together with its review-queue entry and its scheduled publish jobs:

```elixir
Bot.AiBotConfig.meal_types()
|> Task.async_stream(
  fn meal_type ->
    if Bot.bot_recipe_exists?(config.id, meal_type, target_date) do
      :skipped
    else
      generate_one(config, bot_user, meal_type, target_date)
    end
  end,
  timeout: 180_000,
  on_timeout: :kill_task,
  max_concurrency: 2
)
```

```elixir
Repo.transaction(fn ->
  with {:ok, recipe} <- Food.create_recipe(attrs),
       _ <- Posts.create_post(recipe),
       {:ok, bot_recipe} <-
         Bot.create_bot_recipe(%{recipe_id: recipe.id, …, status: "pending_review"}) do
    schedule_publish_jobs(config, bot_recipe, target_date, meal_type)
  else
    {:error, reason} -> Repo.rollback(reason)
  end
end)
```

**The ingredient translator is a self-chaining batch job.** Each run translates 50 untranslated ingredients, inserts with `on_conflict: :nothing`, and enqueues itself again until nothing is left:

```elixir
case IngredientTranslator.translate_to_greek(batch) do
  {:ok, id_to_greek} ->
    insert_translations(id_to_greek)   # insert_all, on_conflict: :nothing
    enqueue_next_batch()               # %{} |> new() |> Oban.insert!()
    :ok
```

Two human/business safeguards sit on top of the technology:

- **Bot-generated recipes are never auto-published.** They enter `pending_review` (`/professional/ai-bot/review`) and an admin approves or rejects each one before the scheduled publish jobs run.
- **User-facing generation is quota-gated** by subscription tier (`Subscriptions.check_quota/2` before, `record_usage/2` after success — see the calendar LiveView snippet above). Free: 0 generations; m3hungry_plus: 15 recipes / 4 plans per month; pro: 30 / 10.

## Design Principles (Summary)

1. **One HTTP client** — auth, retries, parsing in one place (`AI.Client`).
2. **Validate, don't trust** — every ID the model produces is checked against the DB via a `submit_*` tool; errors go back to the model to fix. Legacy fallbacks patch silently; agents correct openly.
3. **The submit tool is the only exit** — an agent run that never submits is a failure, not a silent no-op.
4. **Cheap model for the loop, expensive model for the prose** — Haiku drives tools, Sonnet writes user-visible text.
5. **Degrade gracefully** — legacy pipelines as fallbacks, best-effort prose polish, FTS fallback for vector search, partial plan persistence.
6. **Humans in the loop where it's public** — review queue for bot recipes, quotas for user generation.
7. **Real data over generated data** — USDA API before AI nutrition estimates, with the source tagged.

## Possible Optimizations / Improvements

Found while checking this document against the code. Roughly ordered by expected impact.

### Cost & latency

1. **Anthropic prompt caching.** Every loop iteration re-sends the full system prompt + tool definitions + growing conversation with no `cache_control` markers. Agent runs make 5–16 API calls each, so the (large, static) prefix is re-billed every time. Adding a cache breakpoint after the tool definitions in `AI.Client.build_body/1` would cut input-token cost substantially for every agent run — likely the single highest-leverage change in this layer.

2. **Conversation growth inside the loop.** `AI.Agent.loop/6` appends every tool result forever. A `MealPlanAgent` run that calls `search_catalog` five times carries ~100 recipe entries in context by the time it submits. Older tool results could be truncated or summarized once consumed (e.g. keep only the last N tool-result turns).

3. **Timeout mismatch in the daily worker.** `Task.async_stream(…, timeout: 180_000)` kills a recipe generation after 3 minutes, but a single `RecipeAgent` run can legitimately take longer: up to 10 loop iterations × up to 90s HTTP timeout each, plus the Sonnet polish call, plus 529 backoff sleeps. A slow-API day turns into killed tasks that then re-run on the next Oban attempt. Either raise the per-task timeout or lower `@timeout_ms` / `max_iterations` so the worst case fits.

4. **Embedding cost is per-call and uncached.** `EmbeddingClient.embed/1` does one HTTP call per text. `RecipeEmbeddingWorker.enqueue_all/0` backfills recipes one job per recipe (OpenAI's embeddings endpoint accepts arrays — batch 100 at a time). And both plan agents embed near-identical queries ("light high-protein breakfast") on every run — a Cachex cache for query embeddings (the `geo_cache` pattern already exists in the app) would eliminate most of those calls.

### Robustness

5. **Retry on 429/5xx, with jitter.** `AI.Client` retries only 529 and timeouts. Anthropic signals rate-limiting with **429** (and transient failures with 500/503) — today those fail immediately and kick users onto the legacy fallback unnecessarily. Add them to the retry clause and add jitter to the backoff so the two concurrent `ai_agents` jobs don't retry in lockstep.

6. **Force JSON via tool use instead of fence-stripping.** Every single-shot module does the regex fence-strip dance and treats a malformed shape as total failure. The Messages API can *force* a tool call (`tool_choice: %{type: "tool", name: …}`), which guarantees schema-valid JSON in `input` — no fences, no reprompting. `RecipeTranslator`, `IngredientTranslator`, and `polish_prose` are the natural first candidates. Short of that, extract the duplicated stripping/decoding into one helper (it currently exists in 5+ copies).

7. **~~Process-dictionary result smuggling is fragile.~~ ✅ Done.** `Agent.run/6` now threads an accumulator: the handler is `fn(name, input, acc) -> {result, new_acc}` and `run/6` returns `{:ok, text, final_acc}`. All three agents carry their `:submitted` result and `:offered` provenance set in the accumulator — no more `Process.put(__MODULE__, …)`. The plan agents also gained the same recipe-id provenance gate `RecipeAgent` had for ingredients (a test-covered `validate_plan`/`validate_entries` rejects any id not surfaced by search).

8. **Idempotent persistence would allow retries.** `NutritionistAgentWorker` uses `max_attempts: 1` because a retry after a partial `submit_plan` would duplicate meals. A uniqueness guard on `(user_id, start_dt, title)` for agent-created meals (or an upsert in `persist_entries/2`) would make retries safe and recover today's lost-run failure mode. The same guard would harden `MealPlanAgent` against users double-clicking generate.

### Data & code quality

9. **N+1 queries in `submit_recipe` validation.** `check_ingredient_unit/3` runs `Food.get_ingredient/1` plus a portions query per recipe ingredient — ~20+ queries per submit, and again on every resubmit. Batch them: one query for all ingredient IDs, one for all portions (the helper `get_measurement_unit_portions_for_ingredients/1` already exists and is used by `search_ingredient`).

10. **`submit_plan` loads full recipe structs just for IDs.** Both plan agents do `Food.list_user_recipes(user_id) |> MapSet.new(& &1.id)` — loading every recipe (with whatever preloads that context function does) to build an ID set. A `select: r.id` query would do.

11. **Deduplicate the two plan agents.** `MealPlanAgent` and `NutritionistAgent` share ~70% of their code: slot validation, date-window checks, duplicate-slot detection, `persist_*`, `slot_time/1`. Extract a shared `PlanValidation`/`PlanPersistence` module so the two can't drift (their date validations are already subtly different: one uses `Date.compare`, the other struct comparison operators). Likewise `rerank_by_name` / `filter_by_name_relevance` / `reject_partial_variants` are duplicated between `RecipeAgent` and legacy `RecipeGenerator`.

12. **Centralize model IDs.** `"claude-haiku-4-5-20251001"` and `"claude-sonnet-4-6"` are hardcoded as module attributes in 7 files. A single config (`config :mehungry, :ai_models, loop: …, writer: …`) would make a model upgrade a one-line change and allow per-environment overrides (e.g. a stub model in test).

### Observability & product

13. **~~Token usage is parsed and then dropped.~~ ✅ Done.** `AI.Client` now emits `[:mehungry, :ai, :client, :request, :stop]` per request (`duration` + `input/output_tokens`, tagged by `model`/`status`), and `AI.Agent` emits run + per-tool telemetry tagged by `agent`. `MehungryWeb.PromEx.AiPlugin` aggregates them onto the Prometheus scrape (`mehungry_web_prom_ex_ai_*`), mirrored into LiveDashboard, with `grafana/ai_agents_dashboard.json` for panels — outcome/error rates, iteration-ceiling watch, no-submit retries, and token cost by model. See `docs/infrastructure/observability.md`. Remaining nuance: token cost is attributed by model, not per agent (the client can't see the caller) — thread `usage` back through the loop if per-agent cost matters.

14. **User-facing generation has no progress feedback.** The nutritionist flow streams tool-by-tool progress over PubSub; the consumer create-recipe and meal-plan flows run a `Task.async` and show a static spinner for what can be 1–3 minutes. The `on_event` callback mechanism already exists in `NutritionistAgent` — lifting it into `RecipeAgent`/`MealPlanAgent` and broadcasting from the LiveView would reuse a proven pattern.

15. **Small doc/code drifts.** `RecipeImageWorker`'s moduledoc says "DALL-E 3" but the code uses `gpt-image-1`. The gram measurement unit is looked up by the name `"grammar"` — worth a comment at the lookup site (or a data migration to rename it) so nobody "fixes" the unit name and breaks every agent run.

16. **✅ Fixed (2026-08-14): `recipes.embedding` had no matching schema field, so `RecipeEmbeddingWorker` could never persist an embedding.** `Mehungry.Food.Recipe` didn't declare `field :embedding, ...`, and `Repo.update_all(..., set: [embedding: ...])` validates its `set:` keys against the schema (unlike the `where:`/`order_by:` uses elsewhere, which don't) — so every run raised `Ecto.QueryError: field \`embedding\` in \`update\` does not exist in schema`. Oban retried 3× and discarded; `recipes.embedding` stayed `NULL` for every row and semantic search always returned `[]` from the vector branch. Fixed by adding `field :embedding, Pgvector.Ecto.Vector` to `Recipe`. **Remaining follow-up:** run `RecipeEmbeddingWorker.enqueue_all/0` (maintenance page) once to backfill pre-fix rows. Full writeup in **Recipe Embeddings & Semantic Search**.
