defmodule MehungryLocalAi.PMC.Parser do
  @moduledoc """
  JATS full-text XML → plain text. We only need the running text (composition
  numbers appear inline in results paragraphs and table cells), so this strips tags
  and decodes entities with regexes rather than xmerl — robust against the DTDs and
  named entities that full-text articles carry, which xmerl chokes on.
  """

  # Cap stored/scanned length — some full texts are very large.
  @max_chars 200_000

  @doc "Extract the article body as clean plain text (empty string when there's no body)."
  def to_text(xml) when is_binary(xml) do
    xml
    |> body_fragment()
    |> strip_tags()
    |> decode_entities()
    |> normalize()
    |> String.slice(0, @max_chars)
  end

  def to_text(_), do: ""

  # Prefer the <body>; fall back to the whole document (abstract-only records).
  defp body_fragment(xml) do
    case Regex.run(~r/<body\b[^>]*>(.*)<\/body>/is, xml) do
      [_, body] -> body
      _ -> xml
    end
  end

  defp strip_tags(s), do: Regex.replace(~r/<[^>]+>/u, s, " ")

  defp decode_entities(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> replace_numeric_entities()
    |> replace_hex_entities()
  end

  defp replace_numeric_entities(s),
    do: Regex.replace(~r/&#(\d+);/, s, fn _full, num -> codepoint(String.to_integer(num)) end)

  defp replace_hex_entities(s),
    do: Regex.replace(~r/&#x([0-9a-fA-F]+);/, s, fn _full, hex -> codepoint(String.to_integer(hex, 16)) end)

  defp codepoint(cp) when cp in 0x20..0x10FFFF do
    <<cp::utf8>>
  rescue
    _ -> " "
  end

  defp codepoint(_), do: " "

  defp normalize(s), do: s |> String.replace(~r/\s+/u, " ") |> String.trim()
end
