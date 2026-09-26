defmodule Mehungry.Food.CompoundPlausibilityTest do
  use ExUnit.Case, async: false

  alias Mehungry.Food.CompoundPlausibility

  # Stubs Mehungry.AI.Client via the `:ai_client` seam. Each test scripts one
  # canned response (or an error) under a persistent_term key.
  defmodule StubClient do
    def request(params) do
      :persistent_term.put({__MODULE__, :last_params}, params)

      case :persistent_term.get({__MODULE__, :response}, nil) do
        {:text, text} -> {:ok, %{content: [%{"type" => "text", "text" => text}]}}
        {:error, reason} -> {:error, reason}
        nil -> {:ok, %{content: []}}
      end
    end
  end

  setup do
    Application.put_env(:mehungry, :ai_client, StubClient)

    on_exit(fn ->
      Application.delete_env(:mehungry, :ai_client)
      :persistent_term.erase({StubClient, :response})
      :persistent_term.erase({StubClient, :last_params})
    end)

    :ok
  end

  defp respond(response), do: :persistent_term.put({StubClient, :response}, response)
  defp last_params, do: :persistent_term.get({StubClient, :last_params})

  defp species, do: %{name: "Acerola", scientific_name: "Malpighia emarginata"}
  defp compound, do: %{name: "Ethanol", synonyms: ["ethyl alcohol"], compound_type: "other"}
  defp studies, do: [%{title: "Ethanol extract of acerola", abstract: "Extracted in 80% ethanol."}]

  test "parses a plausible verdict + reason" do
    respond({:text, ~s({"verdict": "plausible", "reason": "real phytochemical"})})

    assert {:ok, %{verdict: :plausible, reason: "real phytochemical"}} =
             CompoundPlausibility.judge(species(), compound(), studies())
  end

  test "parses an implausible verdict" do
    respond({:text, ~s({"verdict": "implausible", "reason": "extraction solvent"})})

    assert {:ok, %{verdict: :implausible, reason: "extraction solvent"}} =
             CompoundPlausibility.judge(species(), compound(), studies())
  end

  test "tolerates markdown fences around the JSON" do
    respond({:text, "```json\n{\"verdict\": \"uncertain\", \"reason\": \"unclear\"}\n```"})

    assert {:ok, %{verdict: :uncertain}} =
             CompoundPlausibility.judge(species(), compound(), studies())
  end

  test "unparseable output is an error (fail-safe upstream)" do
    respond({:text, "I think this is probably fine, honestly."})
    assert {:error, :unparseable} = CompoundPlausibility.judge(species(), compound(), studies())
  end

  test "a client error is propagated" do
    respond({:error, :timeout})
    assert {:error, :timeout} = CompoundPlausibility.judge(species(), compound(), studies())
  end

  test "prompt includes the species, compound, and study context" do
    respond({:text, ~s({"verdict": "plausible", "reason": "ok"})})
    CompoundPlausibility.judge(species(), compound(), studies())

    user = last_params().messages |> hd() |> Map.get(:content)
    assert user =~ "Acerola"
    assert user =~ "Malpighia emarginata"
    assert user =~ "Ethanol"
    assert user =~ "Ethanol extract of acerola"
  end
end
