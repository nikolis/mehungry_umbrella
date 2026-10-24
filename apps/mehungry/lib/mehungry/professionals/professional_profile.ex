defmodule Mehungry.Professionals.ProfessionalProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "professional_profiles" do
    field :specialization, :string
    field :bio, :string

    # Identity / public
    field :display_name, :string
    field :slug, :string
    field :photo_url, :string
    field :is_public, :boolean, default: false

    # Details
    field :education, :string
    field :scientific_contributions, :string
    field :professional_achievements, :string

    # Contact / location
    field :city, :string
    field :region, :string
    field :office_address, :string
    field :phone, :string
    field :contact_email, :string
    field :website_url, :string
    field :timezone, :string

    # Scheduling
    field :appointment_slot_minutes, :integer, default: 60

    # Payments (Stripe Connect — minimal slice). The fee is stored in cents but
    # entered/displayed in euros via the virtual `consultation_fee_eur` field,
    # which the changeset converts both directions (see `put_consultation_fee_cents/1`).
    field :consultation_fee_cents, :integer
    field :consultation_fee_eur, :decimal, virtual: true
    field :stripe_connect_account_id, :string
    field :stripe_charges_enabled, :boolean, default: false

    belongs_to :user, Mehungry.Accounts.User

    has_many :articles, Mehungry.Professionals.Article

    timestamps()
  end

  @editable_fields [
    :user_id,
    :specialization,
    :bio,
    :display_name,
    :photo_url,
    :is_public,
    :education,
    :scientific_contributions,
    :professional_achievements,
    :city,
    :region,
    :office_address,
    :phone,
    :contact_email,
    :website_url,
    :timezone,
    :appointment_slot_minutes
  ]

  @doc """
  Changeset for the nutritionist editing their own profile. Handles all
  public-facing fields, generates a URL slug, and gates `is_public` on
  profile completeness (a public profile must have a display name, city and
  short bio so it renders well and ranks locally).
  """
  def changeset(profile, attrs) do
    profile
    |> seed_consultation_fee_eur()
    |> cast(attrs, [:consultation_fee_eur | @editable_fields])
    |> validate_required([:user_id, :specialization])
    |> validate_length(:specialization, max: 100)
    |> validate_number(:appointment_slot_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_number(:consultation_fee_eur, greater_than_or_equal_to: 0)
    |> validate_format(:contact_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> put_consultation_fee_cents()
    |> maybe_put_slug()
    |> validate_public_completeness()
    |> unique_constraint(:user_id)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:user_id)
  end

  # The form displays/edits the fee in euros, so seed the virtual field from the
  # stored cents before casting — otherwise the input renders blank for a profile
  # that already has a fee. (No-op once the changeset is in flight.)
  defp seed_consultation_fee_eur(%__MODULE__{consultation_fee_cents: cents} = profile) do
    %{profile | consultation_fee_eur: cents_to_eur(cents)}
  end

  # Mirror the euro input back into the stored `consultation_fee_cents` whenever
  # the euro field actually changed (including being cleared → nil).
  defp put_consultation_fee_cents(changeset) do
    case fetch_change(changeset, :consultation_fee_eur) do
      {:ok, eur} -> put_change(changeset, :consultation_fee_cents, eur_to_cents(eur))
      :error -> changeset
    end
  end

  defp cents_to_eur(nil), do: nil
  defp cents_to_eur(cents) when is_integer(cents), do: Decimal.div(Decimal.new(cents), 100)

  defp eur_to_cents(nil), do: nil

  defp eur_to_cents(%Decimal{} = eur),
    do: eur |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  @doc """
  Internal changeset for Stripe Connect state — kept separate from the
  user-editable `changeset/2` so webhooks/onboarding never touch profile copy.
  """
  def stripe_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:stripe_connect_account_id, :stripe_charges_enabled])
  end

  # Generate a slug from display_name (falling back to specialization) the
  # first time one is needed; keep an existing slug stable across edits.
  defp maybe_put_slug(changeset) do
    existing = get_field(changeset, :slug)
    source = get_field(changeset, :display_name) || get_field(changeset, :specialization)

    cond do
      is_binary(existing) and existing != "" -> changeset
      is_nil(source) -> changeset
      true -> put_change(changeset, :slug, slugify(source))
    end
  end

  @doc """
  Slugify a string into a URL-safe slug (lowercase, hyphenated, ascii).
  Public so the context can build collision-avoiding variants.
  """
  def slugify(nil), do: nil

  def slugify(string) do
    string
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.trim()
    |> String.replace(~r/[\s-]+/, "-")
  end

  defp validate_public_completeness(changeset) do
    if get_field(changeset, :is_public) do
      changeset
      |> validate_required([:display_name, :city, :bio],
        message: "is required to make your profile public"
      )
    else
      changeset
    end
  end
end
