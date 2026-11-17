defmodule Mehungry.Food.SpeciesEnrichmentImageTest do
  # async: false — pins the global Wikidata/storage/HTTP seams.
  use Mehungry.DataCase, async: false

  alias Mehungry.Food

  # Fake Wikidata client: returns whatever the test parked in :test_wikidata_result.
  defmodule FakeWikidata do
    @behaviour Mehungry.FoodData.Wikidata.ClientBehaviour

    @impl true
    def fetch(_name, _scientific_name),
      do: {:ok, Application.get_env(:mehungry, :test_wikidata_result, %{})}
  end

  # Storage spy: records each put and returns a stored URL.
  defmodule StorageSpy do
    @behaviour Mehungry.Storage.Behaviour

    def put(key, _binary, _opts) do
      send(Process.get(:spy_pid), {:storage_put, key})
      {:ok, %{url: "https://stub/#{key}", key: key}}
    end

    def get(_key, _opts), do: {:ok, <<>>}
    def delete(_key, _opts), do: {:ok, :deleted}
    def list(_prefix), do: {:ok, []}
    def public_url(key, _opts), do: "https://stub/#{key}"
    def signed_url(key, _e, _o), do: {:ok, "https://stub/#{key}"}
    def signed_urls(keys, _e, _o), do: {:ok, Map.new(keys, &{&1, "https://stub/#{&1}"})}
    def signed_upload(_key, _o), do: {:error, :not_supported}
  end

  @commons_source "https://commons.wikimedia.org/wiki/File:Fennel.jpg"

  setup do
    Process.put(:spy_pid, self())
    Application.put_env(:mehungry, :wikidata_client, FakeWikidata)
    Application.put_env(:mehungry, :storage_impl, StorageSpy)

    Application.put_env(:mehungry, :species_image_http_adapter, fn _url, _h, _o ->
      {:ok, %{status_code: 200, body: "image-bytes"}}
    end)

    on_exit(fn ->
      Application.delete_env(:mehungry, :wikidata_client)
      Application.delete_env(:mehungry, :storage_impl)
      Application.delete_env(:mehungry, :species_image_http_adapter)
      Application.delete_env(:mehungry, :test_wikidata_result)
    end)

    {:ok, sp} = Food.create_foundemental_species(%{name: "Fennel"})
    %{species: sp}
  end

  defp park_image(image), do: Application.put_env(:mehungry, :test_wikidata_result, %{qid: "Q1", image: image})

  defp reusable_image do
    %{
      filename: "Fennel.jpg",
      url: "https://upload.wikimedia.org/thumb/Fennel.jpg/800px-Fennel.jpg",
      original_url: "https://upload.wikimedia.org/Fennel.jpg",
      descriptionurl: @commons_source,
      license_code: "cc-by-sa-3.0",
      license_name: "CC BY-SA 3.0",
      license_url: "https://creativecommons.org/licenses/by-sa/3.0",
      artist: "Alvesgaspar"
    }
  end

  test "stores a free-licensed image and writes all five image_* columns", %{species: sp} do
    park_image(reusable_image())

    Food.enrich_species(sp, source: "wikidata")

    assert_received {:storage_put, "species_images/" <> _}

    reloaded = Food.get_foundemental_species!(sp.id)
    assert reloaded.image_url == "https://stub/species_images/#{sp.id}.jpg"
    assert reloaded.image_license == "CC BY-SA 3.0"
    assert reloaded.image_license_url == "https://creativecommons.org/licenses/by-sa/3.0"
    assert reloaded.image_attribution == "Alvesgaspar"
    assert reloaded.image_source_url == @commons_source
  end

  test "leaves the species image-less when the licence is non-free", %{species: sp} do
    park_image(%{reusable_image() | license_code: "cc-by-nc-4.0", license_name: "CC BY-NC 4.0"})

    Food.enrich_species(sp, source: "wikidata")

    refute_received {:storage_put, _}
    assert is_nil(Food.get_foundemental_species!(sp.id).image_url)
  end

  test "skips the re-download when the same Commons file is already stored", %{species: sp} do
    {:ok, sp} =
      Food.update_foundemental_species(sp, %{
        image_url: "https://stub/species_images/#{sp.id}.jpg",
        image_source_url: @commons_source
      })

    park_image(reusable_image())

    Food.enrich_species(sp, source: "wikidata")

    refute_received {:storage_put, _}
  end
end
