defmodule Mehungry.Professionals.ArticleParagraph do
  @moduledoc """
  One ordered block of an `Article` body: an optional `heading`, a `body` of
  plain text, and an optional per-paragraph `image_url` (+ caption). Its
  `references` are the scientific references cited from this specific paragraph.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Professionals.{Article, ArticleReference}

  @type t :: %__MODULE__{}

  schema "professional_article_paragraphs" do
    field :position, :integer, default: 0
    field :heading, :string
    field :body, :string
    field :image_url, :string
    field :image_caption, :string

    belongs_to :article, Article

    has_many :references, ArticleReference, foreign_key: :paragraph_id

    timestamps()
  end

  def changeset(paragraph, attrs) do
    paragraph
    |> cast(attrs, [:position, :heading, :body, :image_url, :image_caption, :article_id])
    |> validate_required([:article_id])
    |> foreign_key_constraint(:article_id)
  end
end
