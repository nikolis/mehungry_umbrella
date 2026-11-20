defmodule MehungryWeb.Api.V1.BasketJSON do
  @moduledoc "Serializer for the shopping basket (spec §10)."

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Inventory

  def basket(basket, aisles \\ %{}, viewer_id \\ nil) do
    items = loaded(basket.basket_items)

    basket
    |> summary(viewer_id)
    |> Map.put(:items, Enum.map(items, &item(&1, Map.get(aisles, &1.id, "other"))))
    |> data()
  end

  @doc """
  A basket without its items (the `GET /baskets` row), not wrapped. `role` is
  the viewer's role (`"owner"`/`"member"`); `people` is everyone on the list,
  owner first — names and avatars only, never an email.
  """
  def summary(basket, viewer_id \\ nil) do
    people = Inventory.basket_people(basket)

    %{
      id: basket.id,
      title: basket.title,
      updated_at: utc(basket.updated_at),
      items_count: length(loaded(basket.basket_items)),
      role: role(basket, viewer_id),
      shared: length(people) > 1,
      people: Enum.map(people, &person/1)
    }
  end

  defp role(_basket, nil), do: nil

  defp role(basket, viewer_id) do
    case Inventory.basket_role(basket, viewer_id) do
      nil -> nil
      role -> Atom.to_string(role)
    end
  end

  defp person(person) do
    %{
      id: person.id,
      alias: person.name,
      avatar_url: person.avatar_url,
      role: Atom.to_string(person.role)
    }
  end

  @doc "A pending invitation as its owner sees it (`POST`/list on a basket)."
  def invitation(invitation, url \\ nil) do
    %{
      id: invitation.id,
      email: invitation.invitee_email,
      status: invitation.status,
      expires_at: utc(invitation.expires_at),
      # Present only in the response that created it: the token is not stored.
      url: url
    }
  end

  @doc "An invitation as the invitee sees it: who and which list, never its contents."
  def incoming_invitation(invitation) do
    inviter = invitation.inviter

    %{
      id: invitation.id,
      basket_title: invitation.shopping_basket.title,
      inviter:
        inviter &&
          %{
            id: inviter.id,
            alias: Inventory.Sharing.display_name(inviter),
            avatar_url: inviter.profile_pic
          },
      expires_at: utc(invitation.expires_at)
    }
  end

  def item(item, aisle \\ "other") do
    mu = assoc(item.measurement_unit)

    %{
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      in_storage: item.in_storage,
      measurement_unit: mu && %{id: mu.id, name: mu.name},
      recipe_id: item.recipe_id,
      usda_fdc_id: item.usda_fdc_id,
      nutrition_data: item.nutrition_data,
      aisle: aisle,
      # User ids, resolvable against the basket's `people` (nil when unknown or
      # when that person has since left).
      added_by_id: item.added_by_id,
      acquired_by_id: item.acquired_by_id
    }
  end

  defp assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc(value), do: value

  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []
end
