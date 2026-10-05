defmodule Mehungry.Food.Nutrition.FattyAcidMatcher do
  @moduledoc """
  Resolves a fatty-acid nutrient name into its common (trivial) name.

  USDA / FDC report individual fatty acids by their lipid number and class
  prefix rather than their familiar name, e.g. `"SFA 12:0"`, `"MUFA 16:1 c"`,
  `"PUFA 18:2 n-6 c,c"`, `"PUFA 20:5 n-3 (EPA)"`, `"TFA 18:1 t"`. This module
  parses those into the canonical descriptor `(carbons, double_bonds,
  omega_position, trans?)` and maps the result to its common name so callers can
  present "Lauric acid" instead of "SFA 12:0" wherever fatty acids are shown.

  The matching is notation-driven, so it handles any of the class prefixes
  (`SFA`/`MUFA`/`PUFA`/`TFA`) and the trailing geometry/position tokens
  (`c`, `t`, `n-6`, `c,c`, `(EPA)`, …) interchangeably.

      iex> alias Mehungry.Food.Nutrition.FattyAcidMatcher, as: M
      iex> M.common_name("SFA 12:0")
      "Lauric acid"
      iex> M.common_name("MUFA 16:1 c")
      "Palmitoleic acid"
      iex> M.common_name("PUFA 18:2 n-6 c,c")
      "Linoleic acid"
      iex> M.common_name("TFA 18:1 t")
      "Elaidic acid"
      iex> M.common_name("Total Fat")
      nil
  """

  # Each entry: {carbons, double_bonds, omega, trans?} => %{name, abbrev, omega_family}
  #
  # `omega` is the n-x position used to disambiguate positional isomers that
  # share a lipid number (e.g. 18:1 n-9 Oleic vs 18:1 n-7 Vaccenic). When a name
  # carries no position we fall back to the entry whose `omega` is the
  # biologically dominant one for that lipid number (`:default`).
  #
  # `trans?` entries are only consulted when the source name is flagged trans
  # (TFA prefix or an explicit `t`/`trans` token).
  @fatty_acids [
    # ===== Saturated (SFA) — unambiguous by carbon count =====
    %{c: 4, d: 0, name: "Butyric acid"},
    %{c: 5, d: 0, name: "Valeric acid"},
    %{c: 6, d: 0, name: "Caproic acid"},
    %{c: 7, d: 0, name: "Enanthic acid"},
    %{c: 8, d: 0, name: "Caprylic acid"},
    %{c: 9, d: 0, name: "Pelargonic acid"},
    %{c: 10, d: 0, name: "Capric acid"},
    %{c: 11, d: 0, name: "Undecylic acid"},
    %{c: 12, d: 0, name: "Lauric acid"},
    %{c: 13, d: 0, name: "Tridecylic acid"},
    %{c: 14, d: 0, name: "Myristic acid"},
    %{c: 15, d: 0, name: "Pentadecylic acid"},
    %{c: 16, d: 0, name: "Palmitic acid"},
    %{c: 17, d: 0, name: "Margaric acid"},
    %{c: 18, d: 0, name: "Stearic acid"},
    %{c: 19, d: 0, name: "Nonadecylic acid"},
    %{c: 20, d: 0, name: "Arachidic acid"},
    %{c: 21, d: 0, name: "Heneicosylic acid"},
    %{c: 22, d: 0, name: "Behenic acid"},
    %{c: 23, d: 0, name: "Tricosylic acid"},
    %{c: 24, d: 0, name: "Lignoceric acid"},
    %{c: 26, d: 0, name: "Cerotic acid"},

    # ===== Monounsaturated (MUFA) =====
    %{c: 12, d: 1, name: "Lauroleic acid", omega: 3},
    %{c: 14, d: 1, name: "Myristoleic acid", omega: 5},
    %{c: 15, d: 1, name: "Pentadecenoic acid"},
    %{c: 16, d: 1, name: "Palmitoleic acid", omega: 7, omega_family: "Omega-7"},
    %{c: 17, d: 1, name: "Heptadecenoic acid"},
    %{c: 18, d: 1, name: "Oleic acid", omega: 9, omega_family: "Omega-9"},
    %{c: 18, d: 1, name: "Vaccenic acid", omega: 7, omega_family: "Omega-7"},
    %{c: 20, d: 1, name: "Gondoic acid", omega: 9, omega_family: "Omega-9"},
    %{c: 20, d: 1, name: "Gadoleic acid", omega: 11},
    %{c: 22, d: 1, name: "Erucic acid", omega: 9, omega_family: "Omega-9"},
    %{c: 22, d: 1, name: "Cetoleic acid", omega: 11},
    %{c: 24, d: 1, name: "Nervonic acid", omega: 9, omega_family: "Omega-9"},

    # ===== Polyunsaturated (PUFA) =====
    %{c: 18, d: 2, name: "Linoleic acid", omega: 6, omega_family: "Omega-6"},
    %{c: 18, d: 3, name: "Alpha-Linolenic acid", abbrev: "ALA", omega: 3, omega_family: "Omega-3"},
    %{c: 18, d: 3, name: "Gamma-Linolenic acid", abbrev: "GLA", omega: 6, omega_family: "Omega-6"},
    %{c: 18, d: 4, name: "Stearidonic acid", abbrev: "SDA", omega: 3, omega_family: "Omega-3"},
    %{c: 20, d: 2, name: "Eicosadienoic acid", omega: 6, omega_family: "Omega-6"},
    %{c: 20, d: 3, name: "Dihomo-gamma-linolenic acid", abbrev: "DGLA", omega: 6, omega_family: "Omega-6"},
    %{c: 20, d: 3, name: "Eicosatrienoic acid", abbrev: "ETE", omega: 3, omega_family: "Omega-3"},
    %{c: 20, d: 3, name: "Mead acid", omega: 9, omega_family: "Omega-9"},
    %{c: 20, d: 4, name: "Arachidonic acid", abbrev: "ARA", omega: 6, omega_family: "Omega-6"},
    %{c: 20, d: 4, name: "Eicosatetraenoic acid", abbrev: "ETA", omega: 3, omega_family: "Omega-3"},
    %{c: 20, d: 5, name: "Eicosapentaenoic acid", abbrev: "EPA", omega: 3, omega_family: "Omega-3"},
    %{c: 21, d: 5, name: "Heneicosapentaenoic acid", abbrev: "HPA", omega: 3, omega_family: "Omega-3"},
    %{c: 22, d: 2, name: "Docosadienoic acid"},
    %{c: 22, d: 3, name: "Docosatrienoic acid"},
    %{c: 22, d: 4, name: "Adrenic acid", abbrev: "DTA", omega: 6, omega_family: "Omega-6"},
    %{c: 22, d: 5, name: "Docosapentaenoic acid", abbrev: "DPA", omega: 3, omega_family: "Omega-3"},
    %{c: 22, d: 5, name: "Osbond acid", omega: 6, omega_family: "Omega-6"},
    %{c: 22, d: 6, name: "Docosahexaenoic acid", abbrev: "DHA", omega: 3, omega_family: "Omega-3"},

    # ===== Trans isomers (TFA) =====
    %{c: 16, d: 1, name: "Palmitelaidic acid", trans: true},
    %{c: 18, d: 1, name: "Elaidic acid", trans: true},
    %{c: 18, d: 2, name: "Linolelaidic acid", trans: true}
  ]

  # Build {carbons, double_bonds, omega, trans?} => entry maps once at compile time.
  # `omega` key is the integer position, or `:default` for the fallback entry of a
  # lipid number (the first listed for that {c, d} — i.e. the dominant isomer).
  @lookup (fn ->
             by_cd =
               Enum.group_by(@fatty_acids, fn fa -> {fa.c, fa.d, Map.get(fa, :trans, false)} end)

             Enum.reduce(by_cd, %{}, fn {{c, d, trans?}, entries}, acc ->
               acc =
                 Enum.reduce(entries, acc, fn fa, acc ->
                   case Map.get(fa, :omega) do
                     nil -> acc
                     omega -> Map.put(acc, {c, d, omega, trans?}, fa)
                   end
                 end)

               # First listed entry is the dominant isomer used when no position given.
               Map.put(acc, {c, d, :default, trans?}, hd(entries))
             end)
           end).()

  @doc """
  Returns the common (trivial) name for a fatty-acid nutrient name, or `nil`
  when the name is not a recognised fatty acid.
  """
  @spec common_name(String.t() | nil) :: String.t() | nil
  def common_name(name) do
    case match(name) do
      nil -> nil
      fa -> fa.name
    end
  end

  @doc """
  Returns the full matched fatty-acid record (`name`, optional `abbrev`,
  `omega_family`, plus the parsed `carbons`/`double_bonds`/`omega`/`trans?`), or
  `nil` when the name is not a recognised fatty acid.
  """
  @spec match(String.t() | nil) :: map() | nil
  def match(nil), do: nil

  def match(name) when is_binary(name) do
    with {carbons, bonds, omega} <- parse_lipid_number(name) do
      trans? = trans?(name)

      entry =
        lookup(carbons, bonds, omega, trans?) ||
          # A name flagged trans with no dedicated trans entry still resolves to
          # the cis skeleton rather than failing.
          if(trans?, do: lookup(carbons, bonds, omega, false))

      case entry do
        nil ->
          nil

        fa ->
          fa
          |> Map.take([:name, :abbrev, :omega_family])
          |> Map.merge(%{carbons: carbons, double_bonds: bonds, omega: omega, trans?: trans?})
      end
    else
      _ -> nil
    end
  end

  @doc """
  Presentation name for a fatty acid: the common name annotated with its lipid
  number and omega family, e.g. `"Linoleic acid (C18:2, Omega-6)"`. Falls back
  to a title-cased version of the original name when unrecognised, so it is safe
  to call on any nutrient name.
  """
  @spec display_name(String.t() | nil) :: String.t()
  def display_name(name) do
    case match(name) do
      nil ->
        title_case(name)

      fa ->
        suffixes =
          ["C#{fa.carbons}:#{fa.double_bonds}", fa[:omega_family]]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        base = if fa[:abbrev], do: "#{fa.name} (#{fa.abbrev})", else: fa.name
        "#{base} (#{suffixes})"
    end
  end

  @doc "True when the name parses as a fatty-acid lipid number."
  @spec fatty_acid?(String.t() | nil) :: boolean()
  def fatty_acid?(name) when is_binary(name), do: parse_lipid_number(name) != nil
  def fatty_acid?(_), do: false

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  # Extracts {carbons, double_bonds, omega_or_:default} from a name.
  # Handles the USDA notation plus an explicit `C` prefix (`C18:2`).
  defp parse_lipid_number(name) do
    lower = String.downcase(name)

    # Note: no trailing word boundary — USDA glues the cis/trans/iso geometry
    # letter directly onto the bond count ("20:4c", "20:5c", "18:3i"), so a
    # trailing `\b` would drop those entirely. A leading negative-lookbehind
    # keeps us from matching mid-number.
    case Regex.run(~r/(?<!\d)(\d{1,2}):(\d{1,2})/, lower) do
      [_, c, d] ->
        omega =
          case Regex.run(~r/n-(\d{1,2})\b/, lower) do
            [_, o] -> String.to_integer(o)
            _ -> :default
          end

        {String.to_integer(c), String.to_integer(d), omega}

      _ ->
        nil
    end
  end

  defp trans?(name) do
    lower = String.downcase(name)

    String.starts_with?(lower, "tfa") or
      String.contains?(lower, "trans") or
      Regex.match?(~r/\bt\b/, lower) or
      Regex.match?(~r/\d:\d+t\b/, lower)
  end

  defp lookup(carbons, bonds, :default, trans?) do
    Map.get(@lookup, {carbons, bonds, :default, trans?})
  end

  defp lookup(carbons, bonds, omega, trans?) do
    Map.get(@lookup, {carbons, bonds, omega, trans?}) ||
      Map.get(@lookup, {carbons, bonds, :default, trans?})
  end

  defp title_case(nil), do: "Unknown"

  defp title_case(name) do
    name |> String.split(" ") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
  end
end
