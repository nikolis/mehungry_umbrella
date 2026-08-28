defmodule Mehungry.Professionals.Article do
  @moduledoc """
  A long-form, publicly published article authored by a nutritionist
  (`ProfessionalProfile`). The body is a list of ordered `ArticleParagraph`s,
  each of which can carry its own image and its own scientific references
  (`ArticleReference` — PubMed studies, food species, compounds, diseases).

  `status` gates visibility: only `"published"` articles render on the author's
  public profile and are indexed. `slug` is unique across articles and drives the
  public URL `/nutritionists/:profile_slug/articles/:slug`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Professionals.{ProfessionalProfile, ArticleParagraph, ArticleReference}

  @statuses ~w(draft published)

  @type t :: %__MODULE__{}

  schema "professional_articles" do
    field :title, :string
    field :slug, :string
    field :summary, :string
    field :cover_image_url, :string
    field :status, :string, default: "draft"
    field :published_at, :utc_datetime

    belongs_to :professional_profile, ProfessionalProfile

    has_many :paragraphs, ArticleParagraph, preload_order: [asc: :position]
    has_many :references, ArticleReference

    timestamps()
  end

  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :title,
      :slug,
      :summary,
      :cover_image_url,
      :status,
      :published_at,
      :professional_profile_id
    ])
    |> validate_required([:title, :professional_profile_id])
    |> validate_length(:title, max: 200)
    |> validate_inclusion(:status, @statuses)
    |> maybe_put_slug()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:professional_profile_id)
  end

  # Generate a slug from the title the first time one is needed; keep an existing
  # slug stable across edits. Collision disambiguation happens in the context.
  defp maybe_put_slug(changeset) do
    existing = get_field(changeset, :slug)
    source = get_field(changeset, :title)

    cond do
      is_binary(existing) and existing != "" -> changeset
      is_nil(source) -> changeset
      true -> put_change(changeset, :slug, ProfessionalProfile.slugify(source))
    end
  end
end
