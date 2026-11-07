defmodule Mehungry.Professionals.ClinicalConsent do
  @moduledoc """
  A client's GDPR Art. 9 explicit consent to process their special-category
  health data (onboarding questionnaire answers + the body measurements surfaced
  in "My progress") within the nutritionist relationship.

  Recorded per **user** (not per assignment) so it survives a disconnect/reconnect.
  Append-only: a withdrawal stamps `withdrawn_at` instead of deleting, preserving
  the audit trail. `version` pins the consent copy the user agreed to — bumping
  `Mehungry.Professionals.clinical_consent_version/0` forces a re-consent.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "clinical_consents" do
    belongs_to :user, Mehungry.Accounts.User
    field :version, :string
    field :withdrawn_at, :naive_datetime

    timestamps()
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:user_id, :version, :withdrawn_at])
    |> validate_required([:user_id, :version])
    |> foreign_key_constraint(:user_id)
  end
end
