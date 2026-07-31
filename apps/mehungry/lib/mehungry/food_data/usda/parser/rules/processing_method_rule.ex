defmodule Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule do
  @moduledoc """
  Macro for the common rule shape "claim `:processing` tokens for one method".

      defmodule Mehungry.FoodData.Usda.Parser.Rules.SmokedRule do
        use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :smoked
      end

  Together with seed rows for the method's aliases, that module is the entire
  cost of a new processing type.
  """

  defmacro __using__(opts) do
    quote do
      @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

      @method Keyword.fetch!(unquote(opts), :method)

      @impl true
      def apply(result) do
        Mehungry.FoodData.Usda.Parser.Rules.Helpers.claim_processing(result, @method, __MODULE__)
      end
    end
  end
end
