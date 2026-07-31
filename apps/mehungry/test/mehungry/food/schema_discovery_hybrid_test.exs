defmodule Mehungry.Food.SchemaDiscovery.HybridTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.SchemaDiscovery.Hybrid

  describe "cluster_embeddings/1" do
    test "returns one cluster id per embedding, in input order" do
      # e1 ≈ e2 (cosine ≈ 0.99 > 0.8) → same cluster; e3 orthogonal → its own.
      e1 = [1.0, 0.0]
      e2 = [0.99, 0.14]
      e3 = [0.0, 1.0]

      assignments = Hybrid.cluster_embeddings([e1, e2, e3])

      assert length(assignments) == 3, "must be aligned 1:1 with the inputs"
      [a1, a2, a3] = assignments
      assert a1 == a2, "similar embeddings must share a cluster"
      refute a1 == a3, "dissimilar embeddings must not"
    end

    test "groups every similar member together, not just pairs (single-link)" do
      # A chain of near-identical vectors should collapse into one cluster.
      similar = for i <- 0..4, do: [1.0, i * 0.01]

      assignments = Hybrid.cluster_embeddings(similar)

      assert length(assignments) == 5
      assert Enum.uniq(assignments) == [Enum.at(assignments, 0)]
    end

    test "empty input yields no assignments" do
      assert Hybrid.cluster_embeddings([]) == []
    end
  end

  describe "group_embeddings/3 threshold knob" do
    test "the same embeddings split or merge depending on the cutoff" do
      ings = [%{id: 1, name: "alpha"}, %{id: 2, name: "beta"}]
      # cosine(e1, e2) ≈ 0.85
      embs = [[1.0, 0.0], [0.85, 0.5268]]

      assert length(Hybrid.group_embeddings(ings, embs, 0.8)) == 1, "0.85 > 0.8 → merge"
      assert length(Hybrid.group_embeddings(ings, embs, 0.9)) == 2, "0.85 < 0.9 → split"
    end
  end

  describe "cluster label" do
    test "collapses to the single most-representative word, dropping 1-char noise" do
      # Milk names with vitamin A/D noise; identical embeddings → one cluster.
      names = [
        "Milk, whole, 3.25% milkfat, with added vitamin D",
        "Milk, nonfat, fluid, with added vitamin A and vitamin D",
        "Milk, lowfat, fluid, 1% milkfat, with added vitamin A"
      ]

      ings = Enum.map(Enum.with_index(names), fn {n, i} -> %{id: i, name: n} end)
      embs = for _ <- names, do: [1.0, 0.0]

      assert [group] = Hybrid.group_embeddings(ings, embs, 0.8)
      assert group.label == "milk"
    end

    test "breaks frequency ties toward the earlier word" do
      # "beef" and "ground" each appear in both names; "beef" comes first.
      names = ["Beef, ground, raw", "Beef, ground, cooked"]
      ings = Enum.map(Enum.with_index(names), fn {n, i} -> %{id: i, name: n} end)
      embs = for _ <- names, do: [1.0, 0.0]

      assert [group] = Hybrid.group_embeddings(ings, embs, 0.8)
      assert group.label == "beef"
    end
  end

  describe "strip_stopwords/1" do
    test "drops stopwords and keeps the food tokens" do
      assert Hybrid.strip_stopwords("Onions, raw, white") == "onions white"
      assert Hybrid.strip_stopwords("Beef, cooked, with added fat") == "beef"
    end

    test "falls back to the original name when everything is stripped" do
      assert Hybrid.strip_stopwords("raw or cooked") == "raw or cooked"
    end
  end
end
