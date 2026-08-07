defmodule Mix.Tasks.TestAccounts do
  @shortdoc "Seed or reset the three pre-confirmed third-party/bot test accounts"

  @moduledoc """
  Manages the deterministic, pre-confirmed accounts used to exercise
  third-party / bot integrations. Backed by `Mehungry.Accounts.TestAccounts`.

      mix test_accounts            # or: mix test_accounts status
      mix test_accounts seed       # create any missing accounts (idempotent)
      mix test_accounts reset      # delete all three, then recreate fresh

  All three accounts share the password printed in the output.
  """

  use Mix.Task

  alias Mehungry.Accounts.TestAccounts

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    shell = Mix.shell()

    case args do
      ["reset"] ->
        TestAccounts.reset()
        shell.info("Reset 3 test accounts (deleted + recreated).")
        print_status(shell)

      ["seed"] ->
        TestAccounts.seed()
        shell.info("Seeded test accounts.")
        print_status(shell)

      [] ->
        print_status(shell)

      ["status"] ->
        print_status(shell)

      other ->
        shell.error("Unknown args: #{inspect(other)}. Use: seed | reset | status")
    end
  end

  defp print_status(shell) do
    shell.info("Password (all accounts): #{TestAccounts.password()}")

    Enum.each(TestAccounts.status(), fn s ->
      state = if s.exists, do: "exists", else: "missing"
      confirmed = if s[:confirmed], do: "confirmed", else: "unconfirmed"
      shell.info("  #{s.email}  [#{state}, #{confirmed}]")
    end)
  end
end
