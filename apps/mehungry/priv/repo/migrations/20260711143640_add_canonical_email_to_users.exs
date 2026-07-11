defmodule Mehungry.Repo.Migrations.AddCanonicalEmailToUsers do
  use Ecto.Migration

  import Ecto.Query

  alias Mehungry.Repo

  @disable_ddl_transaction false

  def up do
    alter table(:users) do
      add :canonical_email, :citext
    end

    flush()

    backfill_canonical_emails()
  end

  def down do
    alter table(:users) do
      remove :canonical_email
    end
  end

  # Compute the canonical email for every existing row. Kept intentionally
  # self-contained (no app-code dependency) so the migration is stable even if
  # Mehungry.Accounts.User.canonical_email/1 changes later. Logic must mirror it.
  defp backfill_canonical_emails do
    from(u in "users", select: {u.id, u.email})
    |> Repo.all()
    |> Enum.each(fn {id, email} ->
      canonical = canonical_email(email)

      from(u in "users", where: u.id == ^id)
      |> Repo.update_all(set: [canonical_email: canonical])
    end)
  end

  defp canonical_email(email) when is_binary(email) do
    downcased = email |> String.trim() |> String.downcase()

    case String.split(downcased, "@") do
      [local, domain] ->
        local = local |> String.split("+") |> hd()

        {local, domain} =
          if domain in ["gmail.com", "googlemail.com"] do
            {String.replace(local, ".", ""), "gmail.com"}
          else
            {local, domain}
          end

        "#{local}@#{domain}"

      _ ->
        downcased
    end
  end

  defp canonical_email(_), do: nil
end
