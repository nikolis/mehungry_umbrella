defmodule PosTagger do
  def rearrange_with_noun_first(text) do
    case tag_text(text) do
      {:ok, tagged} ->
        # Get the index of the last NOUN
        last_noun_index =
          tagged
          |> Enum.with_index()
          |> Enum.reverse()
          |> Enum.find(fn {{_word, tag}, _idx} -> tag in ["NOUN", "PROPN"] end)
          |> case do
            nil -> nil
            {{_word, _tag}, idx} -> idx
          end

        rearranged =
          cond do
            is_nil(last_noun_index) ->
              Enum.map(tagged, fn {word, _tag} -> word end)

            true ->
              {before, [noun | rest]} = Enum.split(tagged, last_noun_index)

              [noun | before ++ rest]
              |> Enum.map(fn {word, _tag} -> word end)
          end

        {:ok, Enum.join(rearranged, " ")}

      error ->
        error
    end
  end

  def tag_text(text) do
    port = Port.open({:spawn, "python pos_tagger.py"}, [:binary, :exit_status])
    Port.command(port, text)

    receive_output(port, [])
  end

  defp receive_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        lines = String.split(data, "\n", trim: true)

        tagged =
          Enum.map(lines, fn line ->
            case String.split(line, "\t") do
              [word, tag] -> {word, tag}
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        receive_output(port, acc ++ tagged)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, code}} ->
        {:error, "Exited with code #{code}"}
    end
  end
end
