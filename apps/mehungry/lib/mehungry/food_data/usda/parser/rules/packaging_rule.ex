defmodule Mehungry.FoodData.Usda.Parser.Rules.PackagingRule do
  @moduledoc """
  Macro for packaging rules: claims `:packaging` tokens whose canonical value
  matches and sets `result.packaging`.
  """

  defmacro __using__(opts) do
    quote do
      @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

      alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

      @packaging Keyword.fetch!(unquote(opts), :type)

      @impl true
      def apply(result) do
        value = Atom.to_string(@packaging)

        case Enum.filter(Helpers.unconsumed(result, :packaging), &(&1.value == value)) do
          [] ->
            {:ok, result}

          matched ->
            result =
              result
              |> Helpers.consume(matched)
              |> Map.put(:packaging, @packaging)
              |> Helpers.trace_rule(__MODULE__, %{packaging: @packaging})

            {:ok, result}
        end
      end
    end
  end
end
