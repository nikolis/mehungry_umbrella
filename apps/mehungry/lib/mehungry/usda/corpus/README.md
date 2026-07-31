# `USDA.Corpus.*` — corpus-analysis toolkit

A small set of **offline, exploratory** tools for building corpus statistics
over the USDA ingredient corpus. Each `Mehungry.Food.Ingredient`'s `name` is
treated as a *document*; the toolkit tokenizes those names and computes
frequencies, n-grams, and collocation scores.

## Not the parser

This is **separate from** the deterministic description parser
(`Mehungry.FoodData.Usda.Parser.*`, documented in
`docs/usda_description_parser.md`). The parser turns a single description into a
structured food at runtime; this toolkit is a *discovery* aid — you run it in
`iex` to see which tokens, phrases, and collocations dominate the corpus, which
in turn informs **what vocabulary and rules are worth adding to the parser**
(processing methods, parts, portions, grades, …).

Concretely:

- **Different tokenizer.** `USDA.Corpus.Tokenizer` returns a *flat* token list
  and keeps `% / " . -`, so `"3.25%"` and `1/8"` survive as single tokens. The
  parser's `Mehungry.FoodData.Usda.Parser.Tokenizer` instead returns
  segments-of-phrases for the "Primary, qualifier" grammar.
- **Not wired into the app.** No facade delegates, no supervision, no runtime
  callers, no tests. Everything is `iex`-driven and reads straight from the DB.

## Modules

| Module | What it produces |
|---|---|
| `USDA.Corpus.Tokenizer` | `tokenize/1`: text → flat `[token]` (downcase, drop `,()`, scan `~r/[a-z0-9%\/".-]+/`). `tokenize_ingredient_descriptions/0` maps it over all ingredients |
| `USDA.Corpus.Vocabulary` | `build/1` / `build_vacabulary_for_all_ingredients/0`: token → global frequency, sorted desc |
| `USDA.Corpus.Phrases` | `build_document_frequency/0` (per-token document frequency), `build_bigrams/1` & `build_trigrams/1` (n-gram frequencies), and the `ngrams/2` primitive |
| `USDA.Corpus.Cooccurrence` | `build/2`: token co-occurrence matrix, `:document` or `:window` (`radius:`) mode → `%{token => %{neighbor => count}}` |
| `USDA.Corpus.PMI` | `build_pmi/2` / `build_pmi_for_all_ingredients/0`: pointwise mutual information over bigrams — surfaces collocations ("kosher"+"dill") |
| `USDA.Corpus.TFIDF` | `compute_tfidf_for_all_ingredients/0`: TF-IDF per ingredient — surfaces distinctive tokens |

## How they compose

```
Ingredient.name
      │  USDA.Corpus.Tokenizer.tokenize/1
      ▼
   [tokens] ──► Vocabulary.build          (unigram counts)
      │
      ├──► Phrases.build_bigrams/trigrams  (n-gram counts)
      │          │
      │          ▼
      │        PMI.build_pmi               (collocation scores; needs Vocabulary + bigrams)
      │
      ├──► Cooccurrence.build              (neighbour matrix)
      └──► TFIDF.compute...                (per-document distinctiveness; needs document frequency)
```

## Usage (iex)

```elixir
# most frequent tokens across all ingredient names
USDA.Corpus.Vocabulary.build_vacabulary_for_all_ingredients() |> Enum.take(30)

# strongest collocations (highest PMI bigrams)
USDA.Corpus.PMI.build_pmi_for_all_ingredients()
|> Enum.sort_by(fn {_pair, pmi} -> -pmi end)
|> Enum.take(30)

# what tends to appear alongside "beef" (whole-name co-occurrence)
foods = Mehungry.Repo.all(Mehungry.Food.Ingredient)
USDA.Corpus.Cooccurrence.build(foods)["beef"]

# ...or only within a 2-token window
USDA.Corpus.Cooccurrence.build(foods, mode: :window, radius: 2)["beef"]
```

## Known issues / caveats

- `PMI.build_pmi/2` uses `Map.fetch!(vocabulary, token)` — fine when the
  vocabulary and bigrams come from the same corpus, but it will raise on any
  token missing from the vocabulary map.
- Function name typo carried through: `build_vacabulary_for_all_ingredients/0`
  ("vacabulary").
