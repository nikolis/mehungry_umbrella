defmodule MehungrySeasonality do
  @moduledoc """
  **The only door into the seasonality app.** Code outside `apps/mehungry_seasonality`
  calls these functions and nothing else — never the schemas' contexts, the clients or
  the worker directly.

  Seasonality answers, per food species × country × calendar month, two independent
  questions: is the product **locally on the market**, and is it **imported** (and from
  where). The local signal comes from the EU agri-food data portal's producer price
  quotes, the import signal from Eurostat Comext monthly trade. An admin maps species to
  those sources' products, runs a fetch per country, and can override any month.

  See `docs/implementation/seasonality.md`.
  """

  alias MehungrySeasonality.{Core, Countries, Mappings, MonthStatus, Runs, Statuses}

  # ── Countries + species ──────────────────────────────────────────────────────

  @doc "Enabled countries as `%{code, name}` maps."
  defdelegate supported_countries, to: Countries, as: :supported

  @doc "Display name of an ISO country code."
  defdelegate country_name(code), to: Countries, as: :name

  @doc "Every food species as slim `%{id, name, variety}` maps (for the mapping picker)."
  defdelegate list_species, to: Core

  # ── Mappings ─────────────────────────────────────────────────────────────────

  @doc "All species ↔ product mappings."
  defdelegate list_mappings, to: Mappings, as: :list

  @doc "Add a mapping (`foundemental_species_id`, `source`, `external_code`, `label`)."
  defdelegate save_mapping(attrs), to: Mappings, as: :save

  @doc "Remove a mapping by id."
  defdelegate delete_mapping(id), to: Mappings, as: :delete

  @doc "Suggest agri-food portal products for unmapped species. `{:ok, map} | {:error, _}`."
  defdelegate suggest_mappings, to: Mappings, as: :suggest_agridata

  @doc """
  Every portal product with a local signal for a country (mapped or not), each with
  the number of months it is quoted in and a suggested species. `{:ok, list} | {:error, _}`.
  """
  defdelegate available_products(country), to: Mappings

  # ── Fetch runs ───────────────────────────────────────────────────────────────

  @doc "Start a fetch batch for a country. `{:ok, batch_id} | {:error, reason}`."
  defdelegate fetch_country(country), to: Runs

  @doc "Cancel a batch's remaining jobs."
  defdelegate cancel_batch(batch_id), to: Runs

  @doc "The most recent batch id for a country, or nil."
  defdelegate latest_batch_id(country), to: Runs

  @doc "Tracking rows of a batch, species attached."
  defdelegate list_batch_rows(batch_id), to: Runs

  @doc "Progress counts of a batch."
  defdelegate counts_for_batch(batch_id), to: Runs

  @doc "True while a batch has unfinished rows."
  defdelegate batch_in_flight?(batch_id), to: Runs

  @doc "PubSub topic for run progress messages."
  defdelegate runs_topic, to: Runs, as: :topic

  # ── Results ──────────────────────────────────────────────────────────────────

  @doc "The results grid for a country: mapped species × 12 months with raw observations."
  defdelegate grid(country), to: Statuses

  @doc "Hand-set a month's `local` / `imported` / `note`."
  defdelegate override_status(key, attrs), to: Statuses, as: :override

  @doc "Drop a month's overrides and re-derive it."
  defdelegate clear_override(key), to: Statuses

  @doc """
  The twelve monthly statuses of a species in a country, keyed by month — the read
  seam for any future public surface.
  """
  defdelegate for_species(species_id, country), to: Statuses, as: :by_month

  @doc """
  Species ids locally on the market (in season, greenhouse, stored or year-round) in
  `country` in `month` — what the core app's seasonal-availability seam reads (its
  behaviour is implemented in `MehungrySeasonality.Core`, the one door out).
  """
  defdelegate available_species_ids(country, month), to: Statuses

  @doc "The allowed `local` values."
  defdelegate local_values, to: MonthStatus

  @doc "The allowed `imported` values."
  defdelegate imported_values, to: MonthStatus
end
