defmodule Mehungry.MealBlueprints.Blueprint do
  @moduledoc """
  A reusable, user-owned "7-day meal-plan blueprint": a structured targets
  document (7 days × the calendar's meal slots) the user authors by hand. It
  carries no recipes — it is the *aim*, not the plan. A later phase lets the AI
  planner generate an actual calendar week that honours these targets.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.MealBlueprints.BlueprintDay

  schema "meal_blueprints" do
    field :name, :string
    field :description, :string
    # "private" (owner-only) or "public" (browsable + shareable by slug).
    field :visibility, :string, default: "private"
    # URL slug for the public preview page; generated once from the name.
    field :slug, :string
    # Blueprint-level "general" targets (apply across every day): nutrient +
    # bioactive-compound names sourced from the DB via the picker (required +
    # avoid), plus free-text preferred foods.
    field :required_nutrients, {:array, :string}, default: []
    field :avoid_nutrients, {:array, :string}, default: []
    field :required_compounds, {:array, :string}, default: []
    field :avoid_compounds, {:array, :string}, default: []
    field :preferred_foods, {:array, :string}, default: []

    # Populated by list queries for card display; not persisted.
    field :plans_count, :integer, virtual: true

    belongs_to :user, Mehungry.Accounts.User
    # Optional disease scoping the whole blueprint (e.g. "Ulcerative Colitis");
    # applies across all days/meals and seeds the compound suggestions above.
    belongs_to :condition, Mehungry.Health.Condition

    has_many :days, BlueprintDay,
      foreign_key: :blueprint_id,
      preload_order: [asc: :day_index],
      on_replace: :delete

    timestamps()
  end

  @tag_fields [
    :required_nutrients,
    :avoid_nutrients,
    :required_compounds,
    :avoid_compounds,
    :preferred_foods
  ]

  @doc false
  def changeset(blueprint, attrs) do
    blueprint
    |> cast(attrs, [:name, :description, :user_id, :condition_id, :visibility | @tag_fields])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:visibility, ~w(private public))
    |> clean_tags(@tag_fields)
    |> maybe_put_slug()
    |> cast_assoc(:days, with: &BlueprintDay.changeset/2)
    |> validate_day_count()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint(:slug)
  end

  # Generate a URL-safe slug from the name the first time one is needed, with a
  # short random suffix so distinct blueprints (including "Copy of …") never
  # collide; keep an existing slug stable across edits.
  defp maybe_put_slug(changeset) do
    existing = get_field(changeset, :slug)
    name = get_field(changeset, :name)

    cond do
      is_binary(existing) and existing != "" -> changeset
      is_nil(name) -> changeset
      true -> put_change(changeset, :slug, "#{slugify(name)}-#{random_suffix()}")
    end
  end

  @doc "Slugify a string into a URL-safe slug (lowercase, hyphenated, ascii)."
  def slugify(nil), do: "blueprint"

  def slugify(string) do
    slug =
      string
      |> String.downcase()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.trim()
      |> String.replace(~r/[\s-]+/, "-")

    if slug == "", do: "blueprint", else: slug
  end

  defp random_suffix do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false) |> String.downcase()
  end

  # Trim whitespace and drop blank/duplicate tags on each array field; leave a
  # missing value untouched.
  defp clean_tags(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      case get_change(acc, field) do
        nil ->
          acc

        tags ->
          cleaned = tags |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
          put_change(acc, field, cleaned)
      end
    end)
  end

  # The skeleton builder always supplies exactly 7 distinct days (1..7); this
  # guards against a caller submitting a malformed tree.
  defp validate_day_count(changeset) do
    days = get_field(changeset, :days) || []
    indexes = days |> Enum.map(& &1.day_index) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if length(days) == 7 and length(indexes) == 7 do
      changeset
    else
      add_error(changeset, :days, "a blueprint must have exactly 7 distinct days")
    end
  end
end
