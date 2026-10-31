defmodule Mehungry.Professionals.ProfessionalService do
  @moduledoc """
  A priced offering a nutritionist sells — a per-session service or a package
  deal — plus the reserved, free 15-minute intro session.

  `kind`:
    * `"intro"`   — the mandatory free introductory session. Exactly one per
      nutritionist (enforced by a partial unique index). Price is always 0 and
      duration always 15; the nutritionist may edit only its name/description.
    * `"session"` — a single paid consultation.
    * `"package"` — a bundle of several sessions sold at one price
      (`session_count` > 1; composition described in free text for now).

  Money is stored in cents to match `ProfessionalProfile.consultation_fee_cents`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(intro session package)
  @intro_duration_minutes 15

  def kinds, do: @kinds
  def intro_duration_minutes, do: @intro_duration_minutes

  schema "professional_services" do
    field :kind, :string, default: "session"
    field :name, :string
    field :description, :string

    # Stored in cents; entered/displayed in euros via the virtual `price_eur`
    # (converted both directions in the changeset, like ProfessionalProfile).
    field :price_cents, :integer, default: 0
    field :price_eur, :decimal, virtual: true
    field :currency, :string, default: "eur"

    field :duration_minutes, :integer
    field :session_count, :integer, default: 1

    field :active, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :professional, Mehungry.Accounts.User

    timestamps()
  end

  @doc """
  Nutritionist-editable changeset. Intro invariants (free, 15 min, one session)
  are **forced** regardless of submitted values, so an intro can never be
  re-priced or re-timed through the form.
  """
  def changeset(service, attrs) do
    service
    |> seed_price_eur()
    |> cast(attrs, [
      :professional_id,
      :kind,
      :name,
      :description,
      :price_cents,
      :price_eur,
      :currency,
      :duration_minutes,
      :session_count,
      :active,
      :position
    ])
    |> validate_required([:professional_id, :kind, :name])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 120)
    |> validate_number(:price_eur, greater_than_or_equal_to: 0)
    |> validate_number(:session_count, greater_than_or_equal_to: 1)
    |> validate_duration()
    |> put_price_cents()
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> enforce_intro_invariants()
    |> foreign_key_constraint(:professional_id)
    |> unique_constraint(:professional_id,
      name: :professional_services_one_intro,
      message: "already has a free intro session"
    )
  end

  # Seed the virtual euro field from stored cents so the edit form renders a
  # value; no-op once the changeset is in flight.
  defp seed_price_eur(%__MODULE__{price_cents: cents} = service),
    do: %{service | price_eur: cents_to_eur(cents)}

  # Mirror a euro input back into stored cents whenever it actually changed.
  defp put_price_cents(changeset) do
    case fetch_change(changeset, :price_eur) do
      {:ok, eur} -> put_change(changeset, :price_cents, eur_to_cents(eur))
      :error -> changeset
    end
  end

  defp cents_to_eur(nil), do: nil
  defp cents_to_eur(cents) when is_integer(cents), do: Decimal.div(Decimal.new(cents), 100)

  defp eur_to_cents(nil), do: 0

  defp eur_to_cents(%Decimal{} = eur),
    do: eur |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  defp validate_duration(changeset) do
    case get_field(changeset, :duration_minutes) do
      nil -> changeset
      _ -> validate_number(changeset, :duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    end
  end

  # Force the intro to be free / 15 min / single-session no matter what was cast.
  defp enforce_intro_invariants(changeset) do
    if get_field(changeset, :kind) == "intro" do
      changeset
      |> put_change(:price_cents, 0)
      |> put_change(:duration_minutes, @intro_duration_minutes)
      |> put_change(:session_count, 1)
    else
      changeset
    end
  end
end
