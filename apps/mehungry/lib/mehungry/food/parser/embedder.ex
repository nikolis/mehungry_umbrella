defmodule Mehungry.Food.Parser.Embedder do
  @moduledoc """
  Embedding entry point for the USDA parser's semantic layer, referenced by
  `Mehungry.Food.SchemaDiscovery.*`.

  This is a **thin delegator** over `Mehungry.AI.SemanticMatcher`, which owns the
  single Bumblebee serving held by `Mehungry.AI.EmbeddingServer` (gated by the
  `:enable_embeddings` config flag). Keeping one serving avoids loading the model
  twice; this module exists only so parser-side callers can use a
  parser-namespaced name.

  All functions return `{:ok, ...}` / `{:error, reason}` — `:embeddings_disabled`
  when the flag is off, `:serving_not_started` when the server isn't up.
  """

  alias Mehungry.AI.SemanticMatcher

  @doc "Whether the shared embedding serving is available in this node/task."
  defdelegate available?(), to: SemanticMatcher

  @doc "Embed one string → `{:ok, [float]}` (384-dim) or `{:error, reason}`."
  defdelegate embed(text), to: SemanticMatcher

  @doc "Batch-embed strings → `{:ok, [[float]]}` (input order) or `{:error, reason}`."
  defdelegate embed_all(texts), to: SemanticMatcher
end
