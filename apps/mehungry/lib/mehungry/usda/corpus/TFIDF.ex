defmodule USDA.Corpus.TFIDF do
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  def get_exclusions() do
    high_tfidf = compute_tfidf_for_all_ingredients()
    entropies = USDA.Corpus.Phrases.word_entropies() |> Enum.map(fn {x, y} -> x end)
    Enum.filter(high_tfidf, fn {x, _y} -> x in entropies end)
  end

   def get_top_20_percent(items) when is_list(items) do
    # 1. Sort descending by price
    sorted = Enum.sort_by(items, fn {_, price} -> price end, :asc)

    # 2. Calculate how many items represent 20%
    count = length(sorted)
    take_count = ceil(count * 0.5)

    # 3. Take the top items
    Enum.take(sorted, take_count)
   end


  # TF-IDF score (Term Frequency-Inverse Document Frequency) είναι μια αριθμητική στατιστική τιμή που μετρά τη σπουδαιότητα μιας λέξης μέσα σε ένα συγκεκριμένο έγγραφο σε σχέση με μια ολόκληρη συλλογή εγγράφων
  def compute_tfidf_for_all_ingredients() do
    frequencies = USDA.Corpus.Phrases.build_document_frequency()
    total_ingredients = Repo.aggregate(Ingredient, :count, :id)
    frequencies_sorted = Enum.sort_by(frequencies, fn {_key, number} -> number end, :desc)
    IO.inspect(frequencies_sorted, label: "fREQUENCIES")
    IO.inspect(total_ingredients, label: "Total ingredients")

    Repo.all(Ingredient)
    |> Enum.map(fn x -> document_tfidf(x, frequencies, total_ingredients) end)
    |> List.flatten()
    |> Enum.uniq_by(fn {word, _number} -> word end)
    |> get_top_20_percent()
    |> Enum.sort_by(fn {_, number} -> number end)
  end

  def score(term_freq, doc_freq, total_docs) do
    tf = :math.log(1 + term_freq)

    idf =
      :math.log(total_docs / (1 + doc_freq))

    tf * idf
  end

  def document_tfidf(food, document_frequency, total_docs) do
    tokens =
      USDA.Corpus.Tokenizer.tokenize(food.name)

    frequencies =
      Enum.frequencies(tokens)

    Enum.map(frequencies, fn {token, tf} ->
      df = Map.get(document_frequency, token, 1)

      {
        token,
        USDA.Corpus.TFIDF.score(tf, df, total_docs)
      }
    end)
  end
end
