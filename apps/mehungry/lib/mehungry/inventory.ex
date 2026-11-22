defmodule Mehungry.Inventory do
  @moduledoc """
  The Inventory context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient
  alias Mehungry.Inventory.BasketItem
  alias Mehungry.Inventory.BasketParams
  alias Mehungry.PublishedPlans.GroceryAisle

  def change_basket_params(%BasketParams{} = basket_params, attrs \\ %{}) do
    BasketParams.changeset(basket_params, attrs)
  end

  alias Mehungry.Inventory.BasketMember
  alias Mehungry.Inventory.ShoppingBasket

  # One preload shape for every basket loader, so a basket read through any of
  # them is the same struct (items, structured ingredients, and the people it
  # is shared with).
  @basket_preloads [
    basket_items: [:measurement_unit],
    basket_ingredients: [
      :measurement_unit,
      ingredient: [:category, :ingredient_translation]
    ],
    user: :user_profile,
    members: [user: :user_profile]
  ]

  # ── Sharing (invitations, members) lives in Inventory.Sharing ────────────
  alias Mehungry.Inventory.Sharing

  defdelegate invite_to_basket(inviter, basket_id, opts \\ %{}), to: Sharing, as: :invite
  defdelegate preview_invitation(token), to: Sharing
  defdelegate accept_invitation_by_token(user, token), to: Sharing, as: :accept_by_token
  defdelegate accept_basket_invitation(user, invitation_id), to: Sharing, as: :accept
  defdelegate decline_basket_invitation(user, invitation_id), to: Sharing, as: :decline
  defdelegate revoke_basket_invitation(owner, basket_id, invitation_id), to: Sharing, as: :revoke
  defdelegate list_pending_basket_invitations(basket_id), to: Sharing, as: :list_pending
  defdelegate list_basket_invitations_for_user(user_id), to: Sharing, as: :list_for_user
  defdelegate remove_basket_member(actor, basket_id, user_id), to: Sharing, as: :remove_member
  defdelegate basket_people(basket), to: Sharing, as: :people

  # ── Live updates ─────────────────────────────────────────────────────────

  @doc """
  Subscribes the caller to a basket's change topic. Every mutation of the
  basket broadcasts there, whichever client made it, so every open view of a
  shared list stays in step. The process that made the change is not sent its
  own broadcast. Three messages:

    * `{:basket_entry, basket_id, %{op: :upsert | :delete, entry: entry, actor_id: id}}`
      — one line (`BasketItem` / `BasketIngredient`) was added, changed or
      removed. It carries the entry, so a subscriber patches its copy without
      re-reading the list.
    * `{:basket_changed, basket_id}` — anything else (a bulk import, a rename,
      the people on the list): re-read the list.
    * `{:basket_deleted, basket_id}` — the list is gone.

  The nodes are clustered, and old and new releases overlap during a rolling
  deploy, so these shapes must only ever change compatibly.
  """
  def subscribe(basket_id) when not is_nil(basket_id),
    do: Phoenix.PubSub.subscribe(Mehungry.PubSub, topic(basket_id))

  @doc "The PubSub (and mobile channel) topic for a basket."
  def topic(basket_id), do: "basket:#{basket_id}"

  @doc false
  def broadcast_change(basket_id, event \\ :basket_changed)
  def broadcast_change(nil, _event), do: :ok

  # Sent to every subscriber **except the calling process**: the view that made
  # the change already re-reads the list itself, so echoing it back would only
  # make it load everything twice.
  def broadcast_change(basket_id, event) do
    Phoenix.PubSub.broadcast_from(Mehungry.PubSub, self(), topic(basket_id), {event, basket_id})
  end

  @doc false
  # One line changed: send the line itself (see `subscribe/1`).
  def broadcast_entry_change(basket_id, op, entry, actor_id \\ nil)
  def broadcast_entry_change(nil, _op, _entry, _actor_id), do: :ok

  def broadcast_entry_change(basket_id, op, entry, actor_id) when op in [:upsert, :delete] do
    Phoenix.PubSub.broadcast_from(
      Mehungry.PubSub,
      self(),
      topic(basket_id),
      {:basket_entry, basket_id, %{op: op, entry: entry, actor_id: actor_id}}
    )
  end

  # ── Access ───────────────────────────────────────────────────────────────

  @doc """
  The role `user_id` has on a basket: `:owner`, `:member` or `nil` (no access).
  Takes a loaded basket (members preloaded) or a basket id.
  """
  def basket_role(%ShoppingBasket{user_id: user_id}, user_id) when not is_nil(user_id), do: :owner

  def basket_role(%ShoppingBasket{members: members}, user_id) when is_list(members) do
    if Enum.any?(members, &(&1.user_id == user_id)), do: :member
  end

  def basket_role(%ShoppingBasket{id: id}, user_id), do: basket_role(id, user_id)
  def basket_role(nil, _user_id), do: nil
  def basket_role(_basket_id, nil), do: nil

  def basket_role(basket_id, user_id) do
    owner? = from(s in ShoppingBasket, where: s.id == ^basket_id and s.user_id == ^user_id)

    member? =
      from(m in BasketMember, where: m.shopping_basket_id == ^basket_id and m.user_id == ^user_id)

    cond do
      Repo.exists?(owner?) -> :owner
      Repo.exists?(member?) -> :member
      true -> nil
    end
  end

  @doc "Whether `user_id` owns or is a member of the basket."
  def can_access_basket?(user_id, basket_id), do: basket_role(basket_id, user_id) != nil

  @doc """
  Gets a basket by id for someone who **owns it or is a member of it**, or `nil`.
  This is the lookup for reading a list and for item-level changes; list-level
  changes (rename, delete, sharing) stay owner-only via
  `get_user_shopping_basket/2`.
  """
  def get_accessible_basket(user_id, id) do
    from(s in ShoppingBasket,
      left_join: m in BasketMember,
      on: m.shopping_basket_id == s.id and m.user_id == ^user_id,
      where: s.id == ^id and (s.user_id == ^user_id or not is_nil(m.id))
    )
    |> Repo.one()
    |> case do
      nil -> nil
      basket -> Repo.preload(basket, @basket_preloads)
    end
  end

  @doc """
  Returns the list of shopping_baskets.

  ## Examples

      iex> list_shopping_baskets()
      [%ShoppingBasket{}, ...]

  """
  def list_shopping_baskets do
    Repo.all(ShoppingBasket)
  end

  @doc "Every basket the user owns **or is a member of**, fully preloaded."
  def list_shopping_baskets_for_user(user_id) do
    from(s in ShoppingBasket,
      left_join: m in BasketMember,
      on: m.shopping_basket_id == s.id and m.user_id == ^user_id,
      where: s.user_id == ^user_id or not is_nil(m.id),
      order_by: [asc: s.id]
    )
    |> Repo.all()
    |> Repo.preload(@basket_preloads)
  end

  @doc """
  Gets a single shopping_basket.

  Raises `Ecto.NoResultsError` if the Shoping basket does not exist.

  ## Examples

      iex> get_shopping_basket!(123)
      %ShoppingBasket{}

      iex> get_shopping_basket!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket!(id) do
    Repo.get!(ShoppingBasket, id)
    |> Repo.preload(@basket_preloads)
  end

  @doc """
  Gets a basket by id **scoped to its owner**, or `nil` when it does not exist or
  belongs to another user. Use this for any lookup driven by a user-supplied id
  (LiveView events, route params) so one user cannot load another's basket.
  """
  def get_user_shopping_basket(user_id, id) do
    from(s in ShoppingBasket, where: s.id == ^id and s.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      basket -> Repo.preload(basket, @basket_preloads)
    end
  end

  @doc """
  Creates a shopping_basket.

  ## Examples

      iex> create_shopping_basket(%{field: value})
      {:ok, %ShoppingBasket{}}

      iex> create_shopping_basket(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs) do
    result =
      shopping_basket
      |> ShoppingBasket.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        broadcast_change(basket.id)
        {:ok, basket}

      _ ->
        result
    end
  end

  @doc """
  Adds a single `BasketItem` to a basket. `item_params` is a map that may carry
  any of `:name`, `:quantity`, `:measurement_unit_id`, `:description` (a
  free-text unit label, used by the USDA/manual paths that have no
  `MeasurementUnit` row), `:nutrition` (stored into `nutrition_data`) and
  `:usda_fdc_id`. Missing keys are tolerated — e.g. USDA items pass a free-text
  unit via `:description` and no `:measurement_unit_id`. `:added_by_id` records
  who added the line (shown on shared lists).
  """
  def add_item(nil, _item_params), do: {:error, :nil_basket_id}

  def add_item(basket_id, item_params) do
    result =
      %BasketItem{}
      |> BasketItem.changeset(%{
        name: Map.get(item_params, :name),
        quantity: Map.get(item_params, :quantity),
        shopping_basket_id: basket_id,
        measurement_unit_id: Map.get(item_params, :measurement_unit_id),
        description: Map.get(item_params, :description),
        nutrition_data: Map.get(item_params, :nutrition),
        usda_fdc_id: Map.get(item_params, :usda_fdc_id),
        in_storage: false
      })
      |> Ecto.Changeset.put_change(:added_by_id, Map.get(item_params, :added_by_id))
      |> Repo.insert()

    case result do
      {:ok, item} ->
        item = Repo.preload(item, :measurement_unit)
        broadcast_entry_change(basket_id, :upsert, item, item.added_by_id)
        {:ok, item}

      {:error, problem} ->
        {:error, problem}
    end
  end

  @doc """
  Resolves a grocery **aisle** key for each basket item, returning a
  `%{item_id => aisle_key}` map. `BasketItem` carries no category, so — like the
  published-plan weekly list (`PublishedPlans` `group_names_by_aisle`) — we
  resolve the category back from the catalog: by `usda_fdc_id` for USDA items,
  else by the name's normalized `search_name`, then classify with
  `GroceryAisle`. Unmatched names (manual free-text) fall into `"other"`. Runs
  at most two batch queries regardless of item count.
  """
  def aisle_for_items(items) when is_list(items) do
    names =
      items
      |> Enum.map(& &1.name)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    search_names = names |> Enum.map(&Ingredient.normalize_string/1) |> Enum.uniq()
    fdc_ids = items |> Enum.map(& &1.usda_fdc_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    by_search = category_lookup(:search_name, search_names)
    by_fdc = category_lookup(:fdc_id, fdc_ids)

    Map.new(items, fn item ->
      category =
        Map.get(by_fdc, item.usda_fdc_id) ||
          Map.get(by_search, Ingredient.normalize_string(item.name))

      {item.id, GroceryAisle.classify(category)}
    end)
  end

  defp category_lookup(_field, []), do: %{}

  defp category_lookup(field, values) do
    Repo.all(
      from(ing in Ingredient,
        left_join: cat in assoc(ing, :category),
        where: field(ing, ^field) in ^values,
        select: {field(ing, ^field), cat.name}
      )
    )
    |> Map.new()
  end

  @doc """
  Adds all of a recipe's ingredients to a basket as `basket_items`, scaling
  quantities by `servings_scale`. Reads the recipe's `recipe_ingredients`
  (the current schema). `actor_id` is recorded as who added them. Returns
  `{:ok, count}`.
  """
  def add_items_from_recipe(basket_id, recipe, servings_scale \\ 1, actor_id \\ nil) do
    basket = get_shopping_basket!(basket_id)
    recipe = Repo.preload(recipe, recipe_ingredients: [:ingredient, :measurement_unit])
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    items =
      Enum.map(recipe.recipe_ingredients, fn ri ->
        %{
          name: item_name(ri),
          quantity: (ri.quantity || 1) * servings_scale,
          measurement_unit_id: ri.measurement_unit_id,
          shopping_basket_id: basket.id,
          recipe_id: recipe.id,
          added_by_id: actor_id,
          in_storage: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(BasketItem, items)
    broadcast_change(basket.id)
    {:ok, count}
  end

  defp item_name(recipe_ingredient) do
    recipe_ingredient.ingredient_allias ||
      (recipe_ingredient.ingredient && recipe_ingredient.ingredient.name) || "ingredient"
  end

  @doc """
  Returns the user's active basket (most recent), creating an empty "Groceries"
  basket when the user has none. There is no per-row "active" flag — the mobile
  API treats the latest basket as active.
  """
  def get_or_create_basket_for_user(user_id) do
    basket =
      from(s in ShoppingBasket, where: s.user_id == ^user_id, order_by: [desc: s.id], limit: 1)
      |> Repo.one()

    case basket do
      %ShoppingBasket{} = b ->
        get_shopping_basket!(b.id)

      nil ->
        {:ok, created} = create_shopping_basket(%{"user_id" => user_id, "title" => "Groceries"})
        get_shopping_basket!(created.id)
    end
  end

  @doc "Gets a basket item (with its measurement unit)."
  def get_basket_item!(id), do: Repo.get!(BasketItem, id) |> Repo.preload(:measurement_unit)

  @doc """
  Updates a basket item (quantity / in_storage / name …). When the update ticks
  the item off, `actor_id` is recorded as who acquired it; un-ticking clears it.
  A row someone else deleted in the meantime returns `{:error, changeset}`
  rather than raising.
  """
  def update_basket_item(%BasketItem{} = item, attrs, actor_id \\ nil) do
    item
    |> BasketItem.changeset(attrs)
    |> stamp_acquired_by(actor_id)
    |> Repo.update(stale_error_field: :id)
    |> case do
      {:ok, item} ->
        # Forced: the unit may have just changed under an already-loaded one.
        item = Repo.preload(item, :measurement_unit, force: true)
        broadcast_entry_change(item.shopping_basket_id, :upsert, item, actor_id)
        {:ok, item}

      other ->
        other
    end
  end

  defp stamp_acquired_by(changeset, actor_id) do
    case Ecto.Changeset.fetch_change(changeset, :in_storage) do
      {:ok, true} -> Ecto.Changeset.put_change(changeset, :acquired_by_id, actor_id)
      {:ok, _} -> Ecto.Changeset.put_change(changeset, :acquired_by_id, nil)
      :error -> changeset
    end
  end

  @doc """
  Deletes a basket item. Deleting a row another member already deleted is a
  success, not an error.
  """
  def delete_basket_item(%BasketItem{} = item) do
    result = Repo.delete(item, allow_stale: true)
    broadcast_entry_change(item.shopping_basket_id, :delete, item)
    result
  end

  @doc """
  Adds a planned meal's items to a basket: every recipe in the meal contributes
  its ingredients (scaled by consume portions), plus the meal's direct
  ingredients. `actor_id` is recorded as who added them. Returns `{:ok, count}`.
  """
  def add_items_from_meal(basket_id, %Mehungry.History.UserMeal{} = meal, actor_id \\ nil) do
    meal =
      Mehungry.Repo.preload(meal,
        recipe_user_meals: [recipe: [recipe_ingredients: [:ingredient, :measurement_unit]]],
        ingredient_user_meals: [:ingredient, :measurement_unit]
      )

    recipe_added =
      meal.recipe_user_meals
      |> Enum.map(fn rum ->
        {:ok, n} =
          add_items_from_recipe(basket_id, rum.recipe, rum.consume_portions || 1, actor_id)

        n
      end)
      |> Enum.sum()

    basket = get_shopping_basket!(basket_id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    ingredient_items =
      Enum.map(meal.ingredient_user_meals, fn ium ->
        %{
          name: (ium.ingredient && ium.ingredient.name) || "ingredient",
          quantity: ium.quantity || 1,
          measurement_unit_id: ium.measurement_unit_id,
          shopping_basket_id: basket.id,
          added_by_id: actor_id,
          in_storage: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    {ing_count, _} = Repo.insert_all(BasketItem, ingredient_items)
    broadcast_change(basket.id)
    {:ok, recipe_added + ing_count}
  end

  def create_shopping_basket(attrs \\ %{}) do
    result =
      %ShoppingBasket{}
      |> ShoppingBasket.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        {:ok, basket}

      _ ->
        result
    end
  end

  @doc """
  Creates a new shopping basket for `user_id` populated with the aggregated
  ingredients of every meal logged in the inclusive `start_date..end_date` span
  (e.g. the week currently shown on the calendar). Returns `{:ok, basket}` /
  `{:error, changeset}`; the basket is created even when the span has no meals
  (an empty list to start from).
  """
  def create_basket_for_range(user_id, %Date{} = start_date, %Date{} = end_date, title) do
    start_dt = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_dt = NaiveDateTime.new!(end_date, ~T[00:00:00])

    basket_ingredients =
      Mehungry.History.list_history_user_meals_for_user(user_id, start_dt, end_dt)
      |> aggregate_meal_ingredients()

    create_shopping_basket(%{
      "user_id" => user_id,
      "title" => title,
      "start_dt" => start_dt,
      "end_dt" => end_dt,
      "basket_ingredients" => basket_ingredients
    })
  end

  @doc """
  Returns the user's existing shopping basket for the week starting on
  `start_date` (matched on the `start_dt` that `create_basket_for_range/4`
  stamps — Monday 00:00), or `nil`. Lets callers open an already-built week
  list instead of creating a duplicate.
  """
  def get_basket_for_week(user_id, %Date{} = start_date) do
    start_dt = NaiveDateTime.new!(start_date, ~T[00:00:00])

    from(s in ShoppingBasket,
      where: s.user_id == ^user_id and s.start_dt == ^start_dt,
      order_by: [desc: s.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Aggregates a list of `History.UserMeal`s into `basket_ingredients` attrs:
  every recipe ingredient scaled by its meal's logged portions, summed per
  `(ingredient_id, measurement_unit_id)`. Returns a list of string-keyed maps
  (`"ingredient_id"`, `"quantity"`, `"measurement_unit_id"`, `"description"`)
  ready to cast into a `ShoppingBasket`. The meals must be preloaded with
  `recipe_user_meals: [recipe: [recipe_ingredients: [:ingredient_portion, ...]]]`.

  Shared by the basket-builder LiveViews and `create_basket_for_range/4` so the
  scaling/dedup rules live in one place.
  """
  def aggregate_meal_ingredients(user_meals) do
    user_meals
    |> Enum.flat_map(fn meal -> meal.recipe_user_meals end)
    |> Enum.flat_map(fn rum ->
      servings = rum.recipe.servings
      portions = rum.cooking_portions

      Enum.map(rum.recipe.recipe_ingredients, fn ri ->
        {ri.ingredient_id, scaled_quantity(ri.quantity, servings, portions),
         ri.measurement_unit_id, portion_description(ri)}
      end)
    end)
    |> Enum.reduce(%{}, fn {ing, quant_out, mu, desc}, acc ->
      with {ing, quant, mu_e, desc_e} <- Map.get(acc, Integer.to_string(ing)),
           true <- mu == mu_e do
        Map.replace(acc, Integer.to_string(ing), {ing, quant + quant_out, mu_e, desc_e})
      else
        _ -> Map.put_new(acc, Integer.to_string(ing), {ing, quant_out, mu, desc})
      end
    end)
    |> Map.values()
    |> Enum.map(fn {ing, quant, mu, desc} ->
      %{
        "ingredient_id" => ing,
        "quantity" => quant,
        "measurement_unit_id" => mu,
        "description" => desc
      }
    end)
  end

  # Free-text label for a recipe ingredient that uses a description-only portion
  # (no measurement unit), so the basket can still show e.g. "1 medium banana".
  defp portion_description(%{measurement_unit_id: nil, ingredient_portion: %{description: d}}),
    do: d

  defp portion_description(_), do: nil

  # Scales a recipe ingredient's per-recipe quantity to the logged portion:
  # (quantity / servings) * cooking_portions. Any of the three can be missing on
  # older/partial recipe data (nil servings, nil cooking_portions, nil quantity)
  # or servings can be 0 — either of which would raise an ArithmeticError — so
  # default to safe values (servings/portions → 1, qty → 0).
  defp scaled_quantity(quantity, servings, portions) do
    qty = as_number(quantity, 0)
    svgs = as_number(servings, 1)
    svgs = if svgs == 0, do: 1, else: svgs
    prt = as_number(portions, 1)

    Float.round(qty / svgs * prt, 2)
  end

  defp as_number(n, _default) when is_number(n), do: n
  defp as_number(_, default), do: default

  @doc """
  Deletes a shopping_basket.

  ## Examples

      iex> delete_shopping_basket(shopping_basket)
      {:ok, %ShoppingBasket{}}

      iex> delete_shopping_basket(shopping_basket)
      {:error, %Ecto.Changeset{}}

  """
  def delete_shopping_basket(%ShoppingBasket{} = shopping_basket) do
    result = Repo.delete(shopping_basket)
    broadcast_change(shopping_basket.id, :basket_deleted)
    result
  end

  def delete_all_baskets_for_user(user_id) do
    from(basket in ShoppingBasket,
      where: basket.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking shopping_basket changes.

  ## Examples

      iex> change_shopping_basket(shopping_basket)
      %Ecto.Changeset{data: %ShoppingBasket{}}

  """
  def change_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs \\ %{}) do
    ShoppingBasket.changeset(shopping_basket, attrs)
  end

  alias Mehungry.Inventory.BasketIngredient

  @doc """
  Returns the list of basket_ingredients.

  ## Examples

      iex> list_basket_ingredients()
      [%BasketIngredient{}, ...]

  """
  def list_basket_ingredients do
    Repo.all(BasketIngredient)
  end

  @doc """
  Gets a single basket_ingredient.

  Raises `Ecto.NoResultsError` if the Ingredient basket does not exist.

  ## Examples

      iex> get_shopping_basket_ingredient!(123)
      %BasketIngredient{}

      iex> get_shopping_basket_ingredient!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket_ingredient!(id), do: Repo.get!(BasketIngredient, id)

  @doc """
  Creates a basket_ingredient.

  ## Examples

      iex> create_basket_ingredient(%{field: value})
      {:ok, %BasketIngredient{}}

      iex> create_basket_ingredient(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_basket_ingredient(attrs \\ %{}) do
    %BasketIngredient{}
    |> BasketIngredient.changeset(attrs)
    |> Repo.insert()
    |> broadcast_upsert()
  end

  defp broadcast_upsert({:ok, %{shopping_basket_id: basket_id} = entry} = result) do
    broadcast_entry_change(basket_id, :upsert, entry)
    result
  end

  defp broadcast_upsert(result), do: result

  @doc """
  Updates a basket_ingredient.

  ## Examples

      iex> update_basket_ingredient(basket_ingredient, %{field: new_value})
      {:ok, %BasketIngredient{}}

      iex> update_basket_ingredient(basket_ingredient, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs) do
    basket_ingredient
    |> BasketIngredient.changeset(attrs)
    |> Repo.update(stale_error_field: :id)
    |> broadcast_upsert()
  end

  @doc """
  Sets an entry's acquired ("already have it") state to an explicit value,
  recording `actor_id` as who ticked it off. This is the write to use on a
  shared list: it states the outcome the person asked for instead of flipping
  whatever is stored, so two people ticking the same line at once both end up
  with it ticked. Written as a single `UPDATE` so it is safe against a stale
  struct; an entry that no longer exists returns `{:error, :not_found}`.
  """
  def set_acquired(
        %module{id: id, shopping_basket_id: basket_id} = entry,
        acquired?,
        actor_id \\ nil
      )
      when module in [BasketItem, BasketIngredient] and is_boolean(acquired?) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    acquired_by_id = if acquired?, do: actor_id

    {count, _} =
      from(e in module, where: e.id == ^id)
      |> Repo.update_all(
        set: [in_storage: acquired?, acquired_by_id: acquired_by_id, updated_at: now]
      )

    case count do
      0 ->
        {:error, :not_found}

      _ ->
        entry = %{entry | in_storage: acquired?, acquired_by_id: acquired_by_id, updated_at: now}
        broadcast_entry_change(basket_id, :upsert, entry, actor_id)
        {:ok, entry}
    end
  end

  @doc "Flips an entry's acquired state as last read. Prefer `set_acquired/3`."
  def toggle_basket_ingredient(entry, actor_id \\ nil),
    do: set_acquired(entry, not entry.in_storage, actor_id)

  @doc """
  Deletes a basket_ingredient.

  ## Examples

      iex> delete_basket_ingredient(basket_ingredient)
      {:ok, %BasketIngredient{}}

      iex> delete_basket_ingredient(basket_ingredient)
      {:error, %Ecto.Changeset{}}

  """
  def delete_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
    result = Repo.delete(basket_ingredient, allow_stale: true)
    broadcast_entry_change(basket_ingredient.shopping_basket_id, :delete, basket_ingredient)
    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking basket_ingredient changes.

  ## Examples

      iex> change_basket_ingredient(basket_ingredient)
      %Ecto.Changeset{data: %BasketIngredient{}}

  """
  def change_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs \\ %{}) do
    BasketIngredient.changeset(basket_ingredient, attrs)
  end
end
