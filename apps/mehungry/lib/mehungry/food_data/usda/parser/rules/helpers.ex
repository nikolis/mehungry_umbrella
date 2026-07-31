defmodule Mehungry.FoodData.Usda.Parser.Rules.Helpers do
  @moduledoc """
  Shared primitives that enforce the rule idempotence contract described in
  `Mehungry.FoodData.Usda.Parser.Rules.Rule`.
  """

  alias Mehungry.FoodData.Usda.Parser.{Result, Token}

  @doc "Unconsumed tokens of the given type, in classifier (position) order."
  @spec unconsumed(Result.t(), Token.type()) :: [Token.t()]
  def unconsumed(%Result{tokens: tokens}, type) do
    Enum.filter(tokens, &(&1.type == type and not &1.consumed))
  end

  @spec consume(Result.t(), Token.t() | [Token.t()]) :: Result.t()
  def consume(result, %Token{} = token), do: consume(result, [token])

  def consume(%Result{} = result, tokens) when is_list(tokens) do
    positions = MapSet.new(tokens, & &1.position)

    updated =
      Enum.map(result.tokens, fn token ->
        if MapSet.member?(positions, token.position), do: %{token | consumed: true}, else: token
      end)

    %{result | tokens: updated}
  end

  @spec append_unique(list(), term() | list()) :: list()
  def append_unique(list, values) when is_list(values) do
    Enum.reduce(values, list, &append_one(&2, &1))
  end

  def append_unique(list, value), do: append_one(list, value)

  @doc "Trace entry recorded only when a rule changed the result."
  @spec trace_rule(Result.t(), module(), map()) :: Result.t()
  def trace_rule(%Result{} = result, rule, action) do
    Result.put_trace(result, %{stage: :rule, rule: rule, action: action})
  end

  @doc """
  Claims every unconsumed `:processing` token matching `method` and appends
  the method atom to `result.processing`. The shared implementation behind
  `Rules.ProcessingMethodRule`.
  """
  @spec claim_processing(Result.t(), atom(), module()) :: {:ok, Result.t()}
  def claim_processing(%Result{} = result, method, rule) do
    value = Atom.to_string(method)

    case Enum.filter(unconsumed(result, :processing), &(&1.value == value)) do
      [] ->
        {:ok, result}

      matched ->
        result =
          result
          |> consume(matched)
          |> Map.update!(:processing, &append_unique(&1, method))
          |> trace_rule(rule, %{processing: method})

        {:ok, result}
    end
  end

  defp append_one(list, value), do: if(value in list, do: list, else: list ++ [value])
end
