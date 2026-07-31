defmodule Mehungry.FoodData.Usda.Parser.Rules.DescriptorModifierRule do
  @moduledoc """
  Macro for plant-part descriptor rules (seed/leaf/fruit): claims `:modifier`
  tokens matching one word and appends it to `processing_modifiers`.
  """

  defmacro __using__(opts) do
    quote do
      @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

      alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

      @word Keyword.fetch!(unquote(opts), :word)

      @impl true
      def apply(result) do
        case Enum.filter(Helpers.unconsumed(result, :modifier), &(&1.value == @word)) do
          [] ->
            {:ok, result}

          matched ->
            result =
              result
              |> Helpers.consume(matched)
              |> Map.update!(:processing_modifiers, &Helpers.append_unique(&1, @word))
              |> Helpers.trace_rule(__MODULE__, %{modifier: @word})

            {:ok, result}
        end
      end
    end
  end
end
