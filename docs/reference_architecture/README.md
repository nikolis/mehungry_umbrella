# Reference Architecture

Reusable, source-agnostic design patterns — the shape to follow when building a
new feature of the same kind. Distinct from [`../implementation/`](../implementation/) (which
documents specific features as built) and [`../features/`](../features/) (intent).

- [`oban_ui_connected_worker.md`](oban_ui_connected_worker.md) — kick off a large
  Oban job fan-out from a LiveView, then watch it finish live: durable per-unit
  tracking rows as source of truth, dedicated queue, two-tier PubSub broadcast +
  flush-timer coalescing, stream-based O(1) row patches. Distilled from the
  S3 → USDA ingredient-seeding flow.
