defmodule Mehungry.Food.SpeciesIcons do
  @moduledoc """
  Resolves a relevant emoji icon for a `FoundementalFoodSpecies`.

  Deterministic and table-driven — no storage, no AI. `icon_for/1` always
  returns something: a curator's per-species override (`species.icon`) wins;
  otherwise a default is derived from the species' name/variety/alternative
  name by keyword, falling back to its botanical `family`, then a generic
  plate. The keyword table is ordered specific → generic (first match wins), so
  "strawberry" resolves before "berry" and "ground beef" before "beef".

  Extend by adding rows to `@keywords` (most specific first) or `@families`.
  """

  # {substring, emoji} — scanned in order, first containment match wins.
  # Keep more specific terms ABOVE the generic term they'd otherwise shadow.
  @keywords [
    # fruit
    {"strawberr", "🍓"},
    {"blueberr", "🫐"},
    {"raspberr", "🍓"},
    {"blackberr", "🫐"},
    {"cranberr", "🫐"},
    {"currant", "🍇"},
    {"berr", "🍓"},
    {"grapefruit", "🍊"},
    {"grape", "🍇"},
    {"apple", "🍎"},
    {"farro", "🌾"},
    {"balsam-pear", "🥒"},
    {"pear", "🍐"},
    {"banana", "🍌"},
    {"plantain", "🍌"},
    {"orange", "🍊"},
    {"mandarin", "🍊"},
    {"tangerine", "🍊"},
    {"clementine", "🍊"},
    {"lemon", "🍋"},
    {"lime", "🍋"},
    {"pineapple", "🍍"},
    {"mango", "🥭"},
    {"watermelon", "🍉"},
    {"melon", "🍈"},
    {"cantaloupe", "🍈"},
    {"peach", "🍑"},
    {"nectarine", "🍑"},
    {"apricot", "🍑"},
    {"cherr", "🍒"},
    {"kiwi", "🥝"},
    {"coconut", "🥥"},
    {"avocado", "🥑"},
    {"olive", "🫒"},
    {"fig", "🍈"},
    {"date", "🍯"},
    {"pomegranate", "🍎"},
    {"acerola", "🍒"},
    {"carambola", "🍈"},
    {"starfruit", "🍈"},
    {"cherimoya", "🍈"},
    {"carissa", "🍈"},
    {"feijoa", "🍈"},
    {"durian", "🍈"},
    {"abiyuch", "🍈"},
    {"caper", "🫒"},
    # vegetables
    {"tomato", "🍅"},
    {"potato", "🥔"},
    {"sweet potato", "🍠"},
    {"yam", "🍠"},
    {"carrot", "🥕"},
    {"corn", "🌽"},
    {"maize", "🌽"},
    {"eggplant", "🍆"},
    {"aubergine", "🍆"},
    {"bell pepper", "🫑"},
    {"chili", "🌶️"},
    {"chile", "🌶️"},
    {"pepper", "🫑"},
    {"cucumber", "🥒"},
    {"zucchini", "🥒"},
    {"courgette", "🥒"},
    {"lettuce", "🥬"},
    {"spinach", "🥬"},
    {"kale", "🥬"},
    {"cabbage", "🥬"},
    {"chard", "🥬"},
    {"collard", "🥬"},
    {"broccoli", "🥦"},
    {"cauliflower", "🥦"},
    {"brussels", "🥬"},
    {"garlic", "🧄"},
    {"onion", "🧅"},
    {"leek", "🧅"},
    {"shallot", "🧅"},
    {"scallion", "🧅"},
    {"mushroom", "🍄"},
    {"pea", "🫛"},
    {"bean", "🫘"},
    {"lentil", "🫘"},
    {"chickpea", "🫘"},
    {"soy", "🫛"},
    {"peanut", "🥜"},
    {"ginger", "🫚"},
    {"asparagus", "🥬"},
    {"chrysanthemum", "🥬"},
    {"beet", "🥬"},
    {"burdock", "🥔"},
    {"dock", "🥬"},
    {"arrow", "🥔"},
    {"cassava", "🥔"},
    # grains / staples
    {"wheat", "🌾"},
    {"rice", "🌾"},
    {"oat", "🌾"},
    {"barley", "🌾"},
    {"rye", "🌾"},
    {"quinoa", "🌾"},
    {"amaranth", "🌾"},
    {"bulgur", "🌾"},
    {"einkorn", "🌾"},
    {"cattail", "🌾"},
    {"bread", "🍞"},
    # nuts / seeds
    {"almond", "🌰"},
    {"walnut", "🌰"},
    {"cashew", "🌰"},
    {"hazelnut", "🌰"},
    {"pistachio", "🌰"},
    {"chestnut", "🌰"},
    {"nut", "🌰"},
    {"seed", "🌱"},
    # herbs / spices
    {"basil", "🌿"},
    {"mint", "🌿"},
    {"parsley", "🌿"},
    {"cilantro", "🌿"},
    {"coriander", "🌿"},
    {"oregano", "🌿"},
    {"thyme", "🌿"},
    {"rosemary", "🌿"},
    {"sausage", "🌭"},
    {"sage", "🌿"},
    {"herb", "🌿"},
    {"borage", "🌿"},
    {"epazote", "🌿"},
    {"fireweed", "🌿"},
    {"fiddlehead", "🌿"},
    {"drumstick", "🌿"},
    {"agave", "🌵"},
    {"cinnamon", "🪵"},
    {"vanilla", "🍦"},
    {"spice", "🌶️"},
    # animal — meat
    {"cattle", "🐄"},
    {"beef", "🐄"},
    {"veal", "🐄"},
    {"cow", "🐄"},
    {"pork", "🐖"},
    {"pig", "🐖"},
    {"bacon", "🥓"},
    {"ham", "🥓"},
    {"lamb", "🐑"},
    {"mutton", "🐑"},
    {"sheep", "🐑"},
    {"goat", "🐐"},
    {"chicken", "🐔"},
    {"poultry", "🐔"},
    {"turkey", "🦃"},
    {"duck", "🦆"},
    {"rabbit", "🐇"},
    {"goose", "🦆"},
    {"dove", "🕊️"},
    {"emu", "🐦"},
    {"bear", "🐻"},
    {"caribou", "🦌"},
    {"deer", "🦌"},
    {"elk", "🦌"},
    {"salami", "🍖"},
    {"animal product", "🍖"},
    {"meat", "🍖"},
    # animal — seafood
    {"salmon", "🐟"},
    {"tuna", "🐟"},
    {"cod", "🐟"},
    {"trout", "🐟"},
    {"sardine", "🐟"},
    {"anchov", "🐟"},
    {"mackerel", "🐟"},
    {"fish", "🐟"},
    {"shrimp", "🦐"},
    {"prawn", "🦐"},
    {"crab", "🦀"},
    {"lobster", "🦞"},
    {"squid", "🦑"},
    {"octopus", "🐙"},
    {"oyster", "🦪"},
    {"clam", "🦪"},
    {"mussel", "🦪"},
    {"scallop", "🦪"},
    {"cockle", "🦪"},
    {"chiton", "🐚"},
    {"gumboot", "🐚"},
    # dairy & eggs
    {"egg", "🥚"},
    {"milk", "🥛"},
    {"cheese", "🧀"},
    {"butter", "🧈"},
    {"yogurt", "🥛"},
    {"yoghurt", "🥛"},
    # other
    {"honey", "🍯"},
    {"sugar", "🍬"},
    {"cocoa", "🍫"},
    {"chocolate", "🍫"},
    {"coffee", "☕"},
    {"tea", "🍵"},
    {"salt", "🧂"},
    # beverages
    {"beer", "🍺"},
    {"wine", "🍷"},
    {"whiskey", "🥃"},
    {"vodka", "🥃"},
    {"alcoholic", "🍸"},
    # prepared / category buckets
    {"baked", "🍞"},
    {"dessert", "🍰"},
    {"snack", "🍿"},
    {"frozen", "🧊"},
    {"meals", "🍽️"},
    {"sauce", "🥫"},
    {"dip", "🥣"}
  ]

  # Botanical / zoological family → broad emoji, used when no keyword matched.
  @families %{
    "solanaceae" => "🍅",
    "brassicaceae" => "🥬",
    "cucurbitaceae" => "🥒",
    "poaceae" => "🌾",
    "fabaceae" => "🫘",
    "rosaceae" => "🍎",
    "rutaceae" => "🍊",
    "apiaceae" => "🥕",
    "amaryllidaceae" => "🧅",
    "lamiaceae" => "🌿",
    "asteraceae" => "🥬",
    "bovidae" => "🐄",
    "suidae" => "🐖",
    "salmonidae" => "🐟",
    "phasianidae" => "🐔",
    "cervidae" => "🦌",
    "ursidae" => "🐻",
    "anatidae" => "🦆",
    "columbidae" => "🕊️",
    "casuariidae" => "🐦",
    "engraulidae" => "🐟",
    "grossulariaceae" => "🍇",
    "moringaceae" => "🌿",
    "boraginaceae" => "🌿",
    "malpighiaceae" => "🍒",
    "polygonaceae" => "🥬",
    "myrtaceae" => "🍈",
    "annonaceae" => "🍈",
    "oxalidaceae" => "🍈"
  }

  @default "🥗"

  @doc "The emoji for a species: curator override if set, else a derived default."
  def icon_for(%{icon: icon}) when is_binary(icon) and icon != "", do: icon
  def icon_for(species), do: default_icon(species)

  @doc "The derived default emoji (ignores any stored override)."
  def default_icon(species) do
    haystack =
      [Map.get(species, :name), Map.get(species, :variety), Map.get(species, :alternative_name)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map_join(" ", &String.downcase/1)

    keyword_match(haystack) || family_match(Map.get(species, :family)) || @default
  end

  defp keyword_match(haystack) do
    Enum.find_value(@keywords, fn {term, emoji} ->
      if String.contains?(haystack, term), do: emoji
    end)
  end

  defp family_match(family) when is_binary(family),
    do: Map.get(@families, String.downcase(String.trim(family)))

  defp family_match(_), do: nil
end
